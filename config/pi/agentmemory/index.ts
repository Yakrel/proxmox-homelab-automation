import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";
import path from "node:path";
import crypto from "node:crypto";
import { execSync } from "node:child_process";
import { createPlaintextBearerAuthGuard } from "./security.js";

type TextBlock = { type?: string; text?: string };
type AssistantMessage = { role?: string; content?: unknown };
type SmartSearchResult = {
  title?: string;
  narrative?: string;
  type?: string;
  combinedScore?: number;
  score?: number;
  observation?: {
    title?: string;
    narrative?: string;
    type?: string;
  };
};

type HealthResponse = {
  status?: string;
  service?: string;
  version?: string;
  health?: {
    status?: string;
    notes?: string[];
  };
};

type SessionStartResponse = {
  context?: string;
};

type PiProcessState = {
  piSessionKey?: string;
  agentmemorySessionId?: string;
  leaderToken?: string;
  active: boolean;
};

const DEFAULT_URL = process.env.AGENTMEMORY_URL || "http://localhost:3111";
const PROCESS_STATE_KEY = Symbol.for("agentmemory.pi.process-state");
const processGlobal = globalThis as Record<PropertyKey, unknown>;
const processState = (processGlobal[PROCESS_STATE_KEY] as PiProcessState | undefined) ?? { active: false };
processGlobal[PROCESS_STATE_KEY] = processState;
const guardPlaintextBearerAuth = createPlaintextBearerAuthGuard();
const TOOL_GUIDANCE = [
  "agentmemory is available for cross-session memory.",
  "Use memory_search to recall prior decisions, preferences, bugs, and workflows.",
  "Use memory_save when you discover durable facts worth remembering beyond this session.",
].join(" ");
const NOISY_BOOTSTRAP_TYPES = new Set([
  "command_run",
  "file_read",
  "file_write",
  "file_edit",
  "search",
  "web_fetch",
  "conversation",
  "notification",
  "other",
]);

function normalizeBaseUrl(url: string): string {
  return url.replace(/\/+$/, "");
}

function resolveProject(cwd: string): string {
  const explicit = process.env.AGENTMEMORY_PROJECT_NAME?.trim();
  if (explicit) return explicit;
  try {
    const root = execSync("git rev-parse --show-toplevel", {
      cwd,
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 500,
    }).toString().trim();
    if (root) return path.basename(root);
  } catch {}
  return path.basename(cwd);
}

function getText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .flatMap((part) => {
      if (!part || typeof part !== "object") return [] as string[];
      const block = part as TextBlock;
      if (block.type === "text" && typeof block.text === "string") return [block.text];
      return [] as string[];
    })
    .join("\n")
    .trim();
}

function getLastAssistantText(messages: unknown[]): string {
  for (const msg of [...messages].reverse()) {
    if (!msg || typeof msg !== "object") continue;
    const assistant = msg as AssistantMessage;
    if (assistant.role !== "assistant") continue;
    const text = getText(assistant.content);
    if (text) return text;
  }
  return "";
}

function formatSearchResults(results: SmartSearchResult[]): string {
  if (!results.length) return "No relevant memories found.";
  return results
    .slice(0, 5)
    .map((result, index) => {
      const obs = result.observation ?? result;
      const title = obs.title?.trim() || `Memory ${index + 1}`;
      const narrative = obs.narrative?.trim() || "";
      const type = obs.type?.trim() || "memory";
      const score = result.combinedScore ?? result.score;
      const scoreText = typeof score === "number" ? ` [score=${score.toFixed(3)}]` : "";
      return `- ${title} (${type})${scoreText}${narrative ? `: ${narrative}` : ""}`;
    })
    .join("\n");
}

async function callAgentMemory<T>(
  pathname: string,
  options?: {
    method?: "GET" | "POST";
    body?: unknown;
    baseUrl?: string;
  },
): Promise<T | null> {
  const baseUrl = normalizeBaseUrl(options?.baseUrl || process.env.AGENTMEMORY_URL || DEFAULT_URL);
  const method = options?.method || "POST";
  const url = `${baseUrl}/agentmemory/${pathname.replace(/^\/+/, "")}`;
  const headers: Record<string, string> = {};
  const secret = process.env.AGENTMEMORY_SECRET;
  guardPlaintextBearerAuth(baseUrl, secret);
  if (options?.body !== undefined) headers["Content-Type"] = "application/json";
  if (secret) headers.Authorization = `Bearer ${secret}`;

  try {
    const response = await fetch(url, {
      method,
      headers,
      body: options?.body !== undefined ? JSON.stringify(options.body) : undefined,
    });
    if (!response.ok) return null;
    return (await response.json()) as T;
  } catch {
    return null;
  }
}

export default function agentmemoryExtension(pi: ExtensionAPI) {
  const extensionToken = crypto.randomUUID();
  if (process.env.AGENTMEMORY_REQUIRE_HTTPS === "1") {
    guardPlaintextBearerAuth(
      normalizeBaseUrl(process.env.AGENTMEMORY_URL || DEFAULT_URL),
      process.env.AGENTMEMORY_SECRET,
    );
  }
  let sessionId = `ephemeral-${crypto.randomUUID().slice(0, 8)}`;
  let currentProject = process.cwd();
  let lastPrompt = "";
  let lastHealthOk = false;
  let sessionContext = "";
  let bootstrapRecall = "";

  async function getHealth() {
    return await callAgentMemory<HealthResponse>("health", { method: "GET" });
  }

  async function refreshStatus(ctx: { ui: { setStatus: (key: string, text: string) => void } }) {
    const health = await getHealth();
    lastHealthOk = !!health && (health.status === "healthy" || health.health?.status === "healthy");
    ctx.ui.setStatus("agentmemory", lastHealthOk ? "🧠 agentmemory" : "🧠 agentmemory off");
  }

  pi.registerCommand("agentmemory-status", {
    description: "Check local agentmemory server health",
    handler: async (_args, ctx) => {
      const health = await getHealth();
      if (!health) {
        ctx.ui.notify("agentmemory is unreachable at http://localhost:3111", "warning");
        return;
      }
      ctx.ui.notify(
        `agentmemory ${health.status || health.health?.status || "unknown"}${health.version ? ` v${health.version}` : ""}`,
        "info",
      );
    },
  });

  pi.registerTool({
    name: "memory_health",
    label: "Memory Health",
    description: "Check whether the local agentmemory server is reachable and healthy",
    parameters: Type.Object({}),
    async execute() {
      const health = await getHealth();
      if (!health) {
        return {
          content: [{ type: "text", text: "agentmemory is unreachable at http://localhost:3111" }],
          details: { ok: false },
        };
      }
      return {
        content: [
          {
            type: "text",
            text: `agentmemory status: ${health.status || health.health?.status || "unknown"}${health.version ? ` (v${health.version})` : ""}`,
          },
        ],
        details: health,
      };
    },
  });

  pi.registerTool({
    name: "memory_search",
    label: "Memory Search",
    description: "Search agentmemory for cross-session project memory, prior decisions, bugs, and user preferences",
    parameters: Type.Object({
      query: Type.String({ description: "What to search for in memory" }),
      limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 10, default: 5, description: "Maximum results" })),
    }),
    async execute(_toolCallId, params) {
      const result = await callAgentMemory<{ results?: SmartSearchResult[] }>("smart-search", {
        body: { query: params.query, limit: params.limit ?? 5 },
      });
      const results = result?.results || [];
      return {
        content: [{ type: "text", text: formatSearchResults(results) }],
        details: { query: params.query, results },
      };
    },
  });

  pi.registerTool({
    name: "memory_save",
    label: "Memory Save",
    description: "Save a durable fact, convention, workflow, preference, or bug fix into agentmemory",
    parameters: Type.Object({
      content: Type.String({ description: "What should be remembered" }),
      type: Type.Optional(
        Type.String({
          description: "Memory type",
          default: "fact",
        }),
      ),
    }),
    async execute(_toolCallId, params) {
      const result = await callAgentMemory<Record<string, unknown>>("remember", {
        body: { content: params.content, type: params.type || "fact" },
      });
      if (!result) {
        return {
          content: [{ type: "text", text: "Failed to save memory to agentmemory." }],
          details: { ok: false },
        };
      }
      return {
        content: [{ type: "text", text: `Saved memory (${params.type || "fact"}): ${params.content}` }],
        details: result,
      };
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    const sessionFile = ctx.sessionManager.getSessionFile();
    const piSessionId = sessionFile
      ? path.basename(sessionFile).replace(/\.[^.]+$/, "")
      : "ephemeral";
    if (processState.active && processState.piSessionKey === piSessionId) {
      sessionId = processState.agentmemorySessionId!;
      return;
    }
    sessionId = `pi-${piSessionId}-${crypto.randomUUID().slice(0, 8)}`;
    processState.piSessionKey = piSessionId;
    processState.agentmemorySessionId = sessionId;
    processState.leaderToken = extensionToken;
    processState.active = true;
    const cwd = process.cwd();
    currentProject = resolveProject(cwd);
    lastPrompt = "";
    sessionContext = "";
    bootstrapRecall = "";

    const startResult = await callAgentMemory<SessionStartResponse>("session/start", {
      body: {
        sessionId,
        project: currentProject,
        cwd,
        agentId: "pi",
      },
    });
    sessionContext = startResult?.context?.trim() || "";

    const bootstrapResult = await callAgentMemory<{ results?: SmartSearchResult[] }>("smart-search", {
      body: {
        query: `${currentProject} user identity preferences instructions conventions prior decisions workflows`,
        limit: 10,
      },
    });
    const bootstrapResults = (bootstrapResult?.results || [])
      .filter((result) => !NOISY_BOOTSTRAP_TYPES.has((result.observation ?? result).type || ""))
      .slice(0, 5);
    if (bootstrapResults.length) {
      bootstrapRecall = [
        "Durable user and project memory from agentmemory:",
        formatSearchResults(bootstrapResults),
      ].join("\n");
    }
    await refreshStatus(ctx);
  });

  pi.on("before_agent_start", async (event, ctx) => {
    if (processState.leaderToken !== extensionToken) return;
    currentProject = event.systemPromptOptions.cwd || process.cwd();
    lastPrompt = event.prompt?.trim() || "";
    if (!lastPrompt) return;

    const result = await callAgentMemory<{ results?: SmartSearchResult[] }>("smart-search", {
      body: { query: lastPrompt, limit: 5 },
    });
    const results = result?.results || [];
    const recallBlock = results.length
      ? [
          "Relevant long-term memory from agentmemory:",
          formatSearchResults(results),
        ].join("\n")
      : "";

    await refreshStatus(ctx);
    return {
      systemPrompt: [
        event.systemPrompt,
        TOOL_GUIDANCE,
        sessionContext,
        bootstrapRecall,
        recallBlock,
      ].filter(Boolean).join("\n\n"),
    };
  });

  pi.on("agent_end", async (event) => {
    if (processState.leaderToken !== extensionToken) return;
    if (!lastHealthOk || !lastPrompt) return;
    const assistantText = getLastAssistantText(event.messages as unknown[]);
    if (!assistantText) return;
    await callAgentMemory("observe", {
      body: {
        hookType: "post_tool_use",
        sessionId,
        project: currentProject,
        cwd: currentProject,
        timestamp: new Date().toISOString(),
        data: {
          tool_name: "conversation",
          tool_input: lastPrompt.slice(0, 500),
          tool_output: assistantText.slice(0, 4000),
        },
      },
    });
  });

  pi.on("session_shutdown", async () => {
    if (processState.leaderToken !== extensionToken || !processState.active) return;
    processState.active = false;
    await callAgentMemory("session/end", {
      body: { sessionId },
    });
    sessionContext = "";
    bootstrapRecall = "";
    lastPrompt = "";
  });
}
