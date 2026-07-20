import type { Plugin } from "@opencode-ai/plugin";
import { AgentmemoryCapturePlugin as UpstreamPlugin } from "./agentmemory-capture-upstream.ts";

const API = process.env.AGENTMEMORY_URL || "http://localhost:3111";
const SECRET = process.env.AGENTMEMORY_SECRET || "";

function authHeaders(): Record<string, string> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (SECRET) headers["Authorization"] = `Bearer ${SECRET}`;
  return headers;
}

async function post(path: string, body: Record<string, unknown>, timeoutMs = 5000): Promise<void> {
  try {
    await fetch(`${API}/agentmemory${path}`, {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch {}
}

export const AgentmemoryCapturePlugin: Plugin = async (ctx) => {
  const upstream = await UpstreamPlugin(ctx);
  let activeSessionId: string | null = null;

  return {
    ...upstream,

    dispose: async () => {
      if (upstream.dispose) {
        await upstream.dispose();
      }
      if (activeSessionId) {
        await post("/session/end", { sessionId: activeSessionId });
        post("/crystals/auto", { olderThanDays: 7 }, 30000);
        post("/consolidate-pipeline", { tier: "all", force: true }, 30000);
        activeSessionId = null;
      }
    },

    event: async (input) => {
      const type = input.event.type;
      const props = (input.event as any).properties || {};

      if (type === "session.created") {
        const info = props.info as Record<string, unknown> | undefined;
        activeSessionId = (info?.id as string) || props.sessionID || null;
      }

      if (upstream.event) {
        await upstream.event(input);
      }

      if (type === "session.status") {
        const status = props.status as Record<string, unknown> | undefined;
        const sid = props.sessionID || activeSessionId;
        if (sid && status?.type === "idle" && sid !== activeSessionId) {
          await post("/session/end", { sessionId: sid });
        }
      }

      if (type === "session.deleted") {
        const sid = props.info?.id || props.sessionID || activeSessionId;
        if (sid && sid === activeSessionId) {
          activeSessionId = null;
        }
      }
    },
  };
};
