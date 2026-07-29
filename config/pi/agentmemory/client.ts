import { readFileSync } from "node:fs";
import path from "node:path";

export type AgentMemoryErrorKind =
  | "aborted"
  | "configuration"
  | "http"
  | "invalid-json"
  | "network"
  | "timeout";

export type AgentMemoryError = {
  kind: AgentMemoryErrorKind;
  status?: number;
};

export type AgentMemoryResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: AgentMemoryError };

export type RecallRecord = {
  id: string;
  title: string;
  narrative: string;
  type: string;
  score?: number;
  timestamp?: string;
  source: "hybrid" | "lesson" | "scoped";
};

export type RecallFailure = AgentMemoryError & {
  operation: "expand" | "memory-validation" | "scoped-search" | "smart-search";
};

type CompactSearchResult = {
  obsId?: string;
  sessionId?: string;
  title?: string;
  type?: string;
  score?: number;
  timestamp?: string;
};

type CompactLessonResult = {
  lessonId?: string;
  content?: string;
  project?: string;
  score?: number;
  createdAt?: string;
};

type CompactSearchResponse = {
  results?: CompactSearchResult[];
  lessons?: CompactLessonResult[];
};

type ExpandedSearchResult = {
  obsId?: string;
  sessionId?: string;
  observation?: {
    title?: string;
    narrative?: string;
    type?: string;
    timestamp?: string;
  };
};

type ExpandedSearchResponse = {
  results?: ExpandedSearchResult[];
};

type FullSearchResult = {
  sessionId?: string;
  score?: number;
  observation?: {
    id?: string;
    title?: string;
    narrative?: string;
    type?: string;
    timestamp?: string;
  };
};

type FullSearchResponse = {
  results?: FullSearchResult[];
};

type MemoryLookupResponse = {
  memory?: {
    id?: string;
    isLatest?: boolean;
    project?: string;
  };
};

export type ProjectRecall = {
  failures: RecallFailure[];
  records: RecallRecord[];
};

export type CaptureSnapshot = {
  assistantText: string;
  cwd: string;
  project: string;
  promptText: string;
};

type PendingCapture = {
  assistantText: string;
  captureEnabled: boolean;
  cwd: string;
  privateRun: boolean;
  project: string;
  prompts: string[];
  sensitive: boolean;
};

const DEFAULT_TIMEOUT_MS = 5000;
const MAX_TIMEOUT_MS = 30000;
const MIN_TIMEOUT_MS = 1000;
const MAX_CONTEXT_RECORDS = 10;
const MAX_CONTEXT_NARRATIVE_CHARS = 1200;
const TRIVIAL_PROMPT = /^(?:ok(?:ay)?|tamam|peki|evet|hayır|merhaba|selam|teşekkür(?:ler)?|thanks?)[.!\s]*$/iu;

function normalizeBaseUrl(url: string): string {
  return url.replace(/\/+$/, "");
}

function clipped(text: string, limit: number): string {
  if (text.length <= limit) return text;
  return `${text.slice(0, Math.max(0, limit - 1))}…`;
}

function timeoutFromEnvironment(value?: string): number {
  if (!value) return DEFAULT_TIMEOUT_MS;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed)) return DEFAULT_TIMEOUT_MS;
  return Math.min(MAX_TIMEOUT_MS, Math.max(MIN_TIMEOUT_MS, parsed));
}

export function loadAgentMemorySecret(
  env: NodeJS.ProcessEnv = process.env,
  readFile: (filePath: string, encoding: BufferEncoding) => string = readFileSync,
): string {
  const configRoot = env.XDG_CONFIG_HOME?.trim()
    || (env.HOME?.trim() ? path.join(env.HOME, ".config") : "");
  const secretFile = env.AGENTMEMORY_SECRET_FILE?.trim()
    || (configRoot ? path.join(configRoot, "agentmemory", "secret") : "");

  if (secretFile) {
    try {
      const secret = readFile(secretFile, "utf8").trim();
      if (secret) {
        delete env.AGENTMEMORY_SECRET;
        return secret;
      }
    } catch {
      // Fall through to the legacy environment variable for standalone use.
    }
  }

  const legacySecret = env.AGENTMEMORY_SECRET?.trim();
  delete env.AGENTMEMORY_SECRET;
  if (legacySecret) return legacySecret;
  throw new Error("agentmemory: readable non-empty secret file is required");
}

export class AgentMemoryClient {
  readonly baseUrl: string;
  readonly timeoutMs: number;
  private readonly getSecret: () => string;

  constructor(options: {
    baseUrl: string;
    secret: string | (() => string);
    timeoutMs?: number;
  }) {
    this.baseUrl = normalizeBaseUrl(options.baseUrl);
    this.getSecret = typeof options.secret === "function"
      ? options.secret
      : () => options.secret as string;
    this.timeoutMs = options.timeoutMs
      ?? timeoutFromEnvironment(process.env.AGENTMEMORY_TIMEOUT_MS);
  }

  async request<T>(
    pathname: string,
    options?: {
      body?: unknown;
      method?: "GET" | "POST";
      signal?: AbortSignal;
    },
  ): Promise<AgentMemoryResult<T>> {
    const timeoutSignal = AbortSignal.timeout(this.timeoutMs);
    const signal = options?.signal
      ? AbortSignal.any([options.signal, timeoutSignal])
      : timeoutSignal;
    const method = options?.method ?? "POST";
    let secret: string;
    try {
      secret = this.getSecret().trim();
      if (!secret) return { ok: false, error: { kind: "configuration" } };
    } catch {
      return { ok: false, error: { kind: "configuration" } };
    }
    const headers: Record<string, string> = {
      Accept: "application/json",
      Authorization: `Bearer ${secret}`,
    };
    if (options?.body !== undefined) headers["Content-Type"] = "application/json";

    try {
      const response = await fetch(
        `${this.baseUrl}/agentmemory/${pathname.replace(/^\/+/, "")}`,
        {
          body: options?.body !== undefined ? JSON.stringify(options.body) : undefined,
          headers,
          method,
          signal,
        },
      );
      if (!response.ok) {
        return { ok: false, error: { kind: "http", status: response.status } };
      }
      try {
        return { ok: true, value: (await response.json()) as T };
      } catch {
        if (timeoutSignal.aborted) return { ok: false, error: { kind: "timeout" } };
        if (options?.signal?.aborted) return { ok: false, error: { kind: "aborted" } };
        return { ok: false, error: { kind: "invalid-json" } };
      }
    } catch {
      if (timeoutSignal.aborted) return { ok: false, error: { kind: "timeout" } };
      if (options?.signal?.aborted) return { ok: false, error: { kind: "aborted" } };
      return { ok: false, error: { kind: "network" } };
    }
  }
}

export function sanitizeForMemory(input: string): {
  redacted: boolean;
  text: string;
} {
  let redacted = false;
  let text = input.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "");
  const replace = (pattern: RegExp, replacement: string | ((...args: string[]) => string)) => {
    text = text.replace(pattern, (...args) => {
      redacted = true;
      return typeof replacement === "string" ? replacement : replacement(...(args as string[]));
    });
  };

  replace(/<private\b[^>]*>[\s\S]*?<\/private>/giu, "[REDACTED PRIVATE DATA]");
  replace(/<private\b[^>]*>[\s\S]*$/giu, "[REDACTED PRIVATE DATA]");
  replace(
    /-----BEGIN [^-\r\n]*PRIVATE KEY-----[\s\S]*?-----END [^-\r\n]*PRIVATE KEY-----/giu,
    "[REDACTED PRIVATE KEY]",
  );
  replace(/\bBearer\s+[A-Za-z0-9._~+/=-]{8,}/giu, "Bearer [REDACTED]");
  replace(/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/gu, "[REDACTED JWT]");
  replace(
    /\b(?:sk-[A-Za-z0-9_-]{16,}|github_pat_[A-Za-z0-9_]{16,}|gh[pousr]_[A-Za-z0-9_]{16,}|xox[baprs]-[A-Za-z0-9-]{16,}|AKIA[0-9A-Z]{16})\b/gu,
    "[REDACTED TOKEN]",
  );
  replace(
    /\b(https?:\/\/)[^\s/:@]+:[^\s/@]+@/giu,
    (_match, protocol) => `${protocol}[REDACTED]@`,
  );
  replace(
    /([?&](?:access_token|api[_-]?key|password|secret|token)=)[^&#\s]+/giu,
    (_match, prefix) => `${prefix}[REDACTED]`,
  );

  const credentialKey = [
    "api[_-]?key",
    "access[_-]?token",
    "authentication",
    "authorization",
    "auth[_-]?key",
    "auth(?:entication|orization)?[_-]?token",
    "bearer[_-]?token",
    "client[_-]?secret",
    "cookie",
    "credential",
    "db[_-]?password",
    "enc(?:ryption)?[_-]?key",
    "jwt[_-]?secret",
    "master[_-]?key",
    "pass(?:word|wd)",
    "private[_-]?key",
    "secret",
    "secret[_-]?access[_-]?key",
    "signing[_-]?key",
    "token",
  ].join("|");
  const identifierCredential = `(?:[A-Za-z0-9]+[_-])*(?:${credentialKey})`;
  replace(
    new RegExp(
      `((?:["'])?${identifierCredential}(?:["'])?\\s*(?:=|:)\\s*)` +
        `(?:"[^"\\r\\n]*"|'[^'\\r\\n]*'|[^\\s,;}]+)`,
      "giu",
    ),
    (_match, prefix) => `${prefix}[REDACTED]`,
  );
  replace(
    new RegExp(
      `(--${identifierCredential})(?:=|\\s+)(?:"[^"\\r\\n]*"|'[^'\\r\\n]*'|[^\\s,;]+)`,
      "giu",
    ),
    (_match, flag) => `${flag} [REDACTED]`,
  );

  return { redacted, text: text.trim() };
}

function sanitizedRecord(record: RecallRecord): RecallRecord {
  return {
    ...record,
    title: clipped(sanitizeForMemory(record.title).text, 180),
    narrative: clipped(
      sanitizeForMemory(record.narrative).text,
      MAX_CONTEXT_NARRATIVE_CHARS,
    ),
  };
}

function mergeRankedRecords(
  rankedLists: RecallRecord[][],
  limit: number,
): RecallRecord[] {
  const merged = new Map<string, { record: RecallRecord; rankScore: number; order: number }>();
  let order = 0;
  for (const records of rankedLists) {
    records.forEach((record, index) => {
      const existing = merged.get(record.id);
      const rankScore = 1 / (60 + index + 1);
      if (existing) {
        existing.rankScore += rankScore;
        if (record.narrative.length > existing.record.narrative.length) {
          existing.record = record;
        }
        return;
      }
      merged.set(record.id, { record, rankScore, order: order++ });
    });
  }
  return [...merged.values()]
    .sort((a, b) => b.rankScore - a.rankScore || a.order - b.order)
    .slice(0, limit)
    .map(({ record }) => sanitizedRecord(record));
}

export async function recallProjectMemory(options: {
  allowedSessionIds: ReadonlySet<string>;
  client: AgentMemoryClient;
  cwd: string;
  limit: number;
  project: string;
  query: string;
  sessionId: string;
  signal?: AbortSignal;
  tokenBudget?: number;
}): Promise<ProjectRecall> {
  const limit = Math.min(10, Math.max(1, options.limit));
  const safeQuery = sanitizeForMemory(options.query).text;
  if (!safeQuery) return { failures: [], records: [] };

  const [scopedResult, compactResult] = await Promise.all([
    options.client.request<FullSearchResponse>("search", {
      body: {
        cwd: options.cwd,
        format: "full",
        limit: Math.min(100, Math.max(40, limit * 10)),
        project: options.project,
        query: safeQuery,
        token_budget: options.tokenBudget ?? 10000,
      },
      signal: options.signal,
    }),
    options.client.request<CompactSearchResponse>("smart-search", {
      body: {
        includeLessons: true,
        // Smart search is not project-aware. Over-fetch compact metadata so
        // cross-project hits can be removed before the upstream 20-item
        // expansion cap is applied.
        limit: 100,
        project: options.project,
        query: safeQuery,
        sessionId: options.sessionId,
      },
      signal: options.signal,
    }),
  ]);

  const failures: RecallFailure[] = [];
  const scopedRecords: RecallRecord[] = [];
  const hybridRecords: RecallRecord[] = [];
  const lessonRecords: RecallRecord[] = [];

  if (scopedResult.ok && Array.isArray(scopedResult.value.results)) {
    for (const item of scopedResult.value.results) {
      if (!item || typeof item !== "object") continue;
      const observation = item.observation;
      if (!item.sessionId || !observation?.id || !observation.title) continue;
      if (
        !observation.id.startsWith("mem_")
        && !options.allowedSessionIds.has(item.sessionId)
      ) continue;
      scopedRecords.push({
        id: observation.id,
        narrative: observation.narrative ?? "",
        score: item.score,
        source: "scoped",
        timestamp: observation.timestamp,
        title: observation.title,
        type: observation.type ?? "memory",
      });
    }
  } else {
    failures.push({
      operation: "scoped-search",
      ...(scopedResult.ok ? { kind: "invalid-json" as const } : scopedResult.error),
    });
  }

  if (compactResult.ok && Array.isArray(compactResult.value.results)) {
    const lessons = compactResult.value.lessons;
    if (lessons !== undefined && !Array.isArray(lessons)) {
      failures.push({ operation: "smart-search", kind: "invalid-json" });
    }
    for (const lesson of Array.isArray(lessons) ? lessons : []) {
      if (!lesson || typeof lesson !== "object") continue;
      if (!lesson.lessonId || !lesson.content) continue;
      if (lesson.project !== options.project) continue;
      lessonRecords.push({
        id: lesson.lessonId,
        narrative: lesson.content,
        score: lesson.score,
        source: "lesson",
        timestamp: lesson.createdAt,
        title: "Learned project lesson",
        type: "lesson",
      });
    }

    const compactItems = (compactResult.value.results ?? []).filter(
      (item): item is CompactSearchResult & { obsId: string; sessionId: string } =>
        !!item
        && typeof item === "object"
        && !!item.obsId
        && !!item.sessionId
        && !item.obsId.startsWith("mem_")
        && options.allowedSessionIds.has(item.sessionId),
    );
    if (compactItems.length) {
      const expandedResult = await options.client.request<ExpandedSearchResponse>("smart-search", {
        body: {
          expandIds: compactItems.slice(0, 20).map((item) => ({
            obsId: item.obsId,
            sessionId: item.sessionId,
          })),
        },
        signal: options.signal,
      });
      if (expandedResult.ok && Array.isArray(expandedResult.value.results)) {
        const compactById = new Map(compactItems.map((item) => [item.obsId, item]));
        for (const item of expandedResult.value.results ?? []) {
          if (!item || typeof item !== "object") continue;
          if (!item.obsId || !item.sessionId || !item.observation) continue;
          if (!options.allowedSessionIds.has(item.sessionId)) continue;
          const compact = compactById.get(item.obsId);
          hybridRecords.push({
            id: item.obsId,
            narrative: item.observation.narrative ?? "",
            score: compact?.score,
            source: "hybrid",
            timestamp: item.observation.timestamp ?? compact?.timestamp,
            title: item.observation.title ?? compact?.title ?? "Memory",
            type: item.observation.type ?? compact?.type ?? "memory",
          });
        }
      } else {
        failures.push({
          operation: "expand",
          ...(expandedResult.ok ? { kind: "invalid-json" as const } : expandedResult.error),
        });
      }
    }
  } else {
    failures.push({
      operation: "smart-search",
      ...(compactResult.ok ? { kind: "invalid-json" as const } : compactResult.error),
    });
  }

  const candidates = mergeRankedRecords(
    [hybridRecords, scopedRecords, lessonRecords],
    40,
  );
  const validated = await Promise.all(candidates.map(async (record) => {
    if (!record.id.startsWith("mem_")) return record;
    const result = await options.client.request<MemoryLookupResponse>(
      `memories/${encodeURIComponent(record.id)}`,
      { method: "GET", signal: options.signal },
    );
    if (!result.ok) {
      failures.push({ operation: "memory-validation", ...result.error });
      return null;
    }
    const memory = result.value.memory;
    if (!memory || memory.id !== record.id) {
      failures.push({ operation: "memory-validation", kind: "invalid-json" });
      return null;
    }
    if (memory.isLatest === false) return null;
    if (memory.project !== options.project) return null;
    return record;
  }));

  return {
    failures,
    records: validated
      .filter((record): record is RecallRecord => record !== null)
      .slice(0, limit),
  };
}

export function serializeUntrustedMemory(options: {
  bootstrapRecords?: RecallRecord[];
  recallRecords?: RecallRecord[];
}): string {
  const bootstrapRecords = (options.bootstrapRecords ?? [])
    .slice(0, MAX_CONTEXT_RECORDS)
    .map(sanitizedRecord);
  const recallRecords = (options.recallRecords ?? [])
    .slice(0, MAX_CONTEXT_RECORDS)
    .map(sanitizedRecord);
  return JSON.stringify({
    bootstrapRecords,
    recallRecords,
    source: "agentmemory",
    trust: "untrusted-reference-data",
  });
}

export function isSubstantiveConversation(prompt: string, assistantText: string): boolean {
  const normalizedPrompt = prompt.replace(/\s+/g, " ").trim();
  const normalizedAssistant = assistantText.replace(/\s+/g, " ").trim();
  if (!normalizedPrompt || !normalizedAssistant) return false;
  if (TRIVIAL_PROMPT.test(normalizedPrompt)) return false;
  return normalizedPrompt.length >= 20 || normalizedAssistant.length >= 120;
}

export class ConversationCapture {
  private pending?: PendingCapture;

  begin(options: {
    captureEnabled: boolean;
    cwd: string;
    initialPrompt: string;
    privateRun: boolean;
    project: string;
  }): void {
    const initialPrompt = sanitizeForMemory(options.initialPrompt);
    this.pending = {
      assistantText: "",
      captureEnabled: options.captureEnabled,
      cwd: options.cwd,
      privateRun: options.privateRun,
      project: options.project,
      prompts: initialPrompt.text ? [initialPrompt.text] : [],
      sensitive: initialPrompt.redacted,
    };
  }

  addUserMessage(message: string): void {
    if (!this.pending || this.pending.privateRun) return;
    const sanitized = sanitizeForMemory(message);
    this.pending.sensitive ||= sanitized.redacted;
    if (!sanitized.text || this.pending.prompts.at(-1) === sanitized.text) return;
    this.pending.prompts.push(sanitized.text);
  }

  setAssistantText(message: string): void {
    if (!this.pending || this.pending.privateRun) return;
    const sanitized = sanitizeForMemory(message);
    this.pending.sensitive ||= sanitized.redacted;
    this.pending.assistantText = sanitized.text;
  }

  settle(): CaptureSnapshot | null {
    const pending = this.pending;
    this.pending = undefined;
    if (
      !pending
      || !pending.captureEnabled
      || pending.privateRun
      || pending.sensitive
    ) return null;
    const promptText = pending.prompts.join("\n\n").trim();
    const assistantText = pending.assistantText.trim();
    if (!isSubstantiveConversation(promptText, assistantText)) return null;
    return {
      assistantText: clipped(assistantText, 4000),
      cwd: pending.cwd,
      project: pending.project,
      promptText: clipped(promptText, 1000),
    };
  }

  reset(): void {
    this.pending = undefined;
  }
}
