import assert from "node:assert/strict";
import http from "node:http";
import path from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";

const bundlePath = process.env.AGENTMEMORY_EXTENSION_BUNDLE
  || "/tmp/agentmemory-extension-test.mjs";

async function startServer(handler) {
  const server = http.createServer(handler);
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  assert.equal(typeof address, "object");
  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    close: async () => {
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
    },
  };
}

async function jsonBody(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return chunks.length
    ? JSON.parse(Buffer.concat(chunks).toString("utf8"))
    : null;
}

function createPiMock() {
  const commands = new Map();
  const handlers = new Map();
  const sentMessages = [];
  const tools = new Map();
  return {
    api: {
      on(event, handler) {
        handlers.set(event, handler);
      },
      registerCommand(name, command) {
        commands.set(name, command);
      },
      registerTool(tool) {
        tools.set(tool.name, tool);
      },
      sendMessage(message, options) {
        sentMessages.push({ message, options });
      },
    },
    commands,
    handlers,
    sentMessages,
    tools,
  };
}

test("Pi lifecycle keeps recall ephemeral, private runs isolated, and capture final-only", async () => {
  let activeProject = "";
  let activeSessionId = "";
  let healthStatus = "healthy";
  let observeCount = 0;
  let rememberCount = 0;
  const requests = [];
  const server = await startServer(async (request, response) => {
    assert.equal(request.headers.authorization, "Bearer lifecycle-test-secret");
    const body = await jsonBody(request);
    requests.push({ body, method: request.method, path: request.url });
    response.setHeader("content-type", "application/json");

    if (request.url === "/agentmemory/session/start") {
      activeProject = body.project;
      activeSessionId = body.sessionId;
      response.end(JSON.stringify({ session: { id: activeSessionId } }));
      return;
    }
    if (request.url === "/agentmemory/sessions?agentId=pi") {
      response.end(JSON.stringify({
        sessions: [
          { cwd: process.cwd(), id: activeSessionId, project: activeProject },
          { cwd: process.cwd(), id: "legacy-session", project: path.basename(process.cwd()) },
          { cwd: "/different/repository", id: "other-session", project: activeProject },
        ],
      }));
      return;
    }
    if (request.url === "/agentmemory/search") {
      response.end(JSON.stringify({
        format: "full",
        results: [{
          observation: {
            id: "obs-legacy",
            narrative: "A scoped prior architecture decision.",
            title: "Prior decision",
            type: "architecture",
          },
          score: 1,
          sessionId: "legacy-session",
        }],
      }));
      return;
    }
    if (request.url === "/agentmemory/smart-search") {
      response.end(JSON.stringify({ lessons: [], mode: "compact", results: [] }));
      return;
    }
    if (request.url === "/agentmemory/health") {
      response.end(JSON.stringify({ status: healthStatus, version: "0.9.28" }));
      return;
    }
    if (request.url === "/agentmemory/observe") {
      observeCount++;
      response.statusCode = 201;
      response.end(JSON.stringify({ observationId: `obs-${observeCount}` }));
      return;
    }
    if (request.url === "/agentmemory/remember") {
      rememberCount++;
      response.statusCode = 201;
      response.end(JSON.stringify({ success: true, memory: { id: "mem_saved" } }));
      return;
    }
    if (request.url === "/agentmemory/session/end") {
      response.end(JSON.stringify({ success: true }));
      return;
    }
    response.statusCode = 404;
    response.end(JSON.stringify({ error: "not found" }));
  });

  const previous = {
    AGENTMEMORY_SECRET: process.env.AGENTMEMORY_SECRET,
    AGENTMEMORY_SECRET_FILE: process.env.AGENTMEMORY_SECRET_FILE,
    AGENTMEMORY_URL: process.env.AGENTMEMORY_URL,
    XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME,
  };
  process.env.AGENTMEMORY_SECRET = "lifecycle-test-secret";
  delete process.env.AGENTMEMORY_SECRET_FILE;
  process.env.AGENTMEMORY_URL = server.baseUrl;
  process.env.XDG_CONFIG_HOME = "/tmp/agentmemory-extension-test-no-config";

  try {
    const { default: extension } = await import(pathToFileURL(bundlePath).href);
    const mock = createPiMock();
    extension(mock.api);

    const statuses = [];
    const notifications = [];
    const ctx = {
      cwd: process.cwd(),
      isIdle: () => true,
      sessionManager: {
        getSessionFile: () => "/tmp/pi-lifecycle-session.jsonl",
      },
      signal: undefined,
      ui: {
        notify: (message, level) => notifications.push({ level, message }),
        setStatus: (key, value) => statuses.push({ key, value }),
      },
    };

    await mock.handlers.get("session_start")({}, ctx);
    assert.match(activeProject, /^proxmox-homelab-automation-[0-9a-f]{12}$/);

    const before = await mock.handlers.get("before_agent_start")({
      prompt: "Please apply the existing architecture decision to this implementation",
      systemPrompt: "BASE",
      systemPromptOptions: { cwd: process.cwd() },
    }, ctx);
    assert.equal("message" in before, false);
    assert.match(before.systemPrompt, /untrusted reference data/);

    const originalMessages = [{ role: "user", content: [{ type: "text", text: "prompt" }], timestamp: 1 }];
    const context = mock.handlers.get("context")({ messages: originalMessages });
    assert.equal(originalMessages.length, 1);
    assert.equal(context.messages.length, 2);
    const ephemeral = context.messages[0];
    assert.equal(ephemeral.role, "custom");
    assert.equal(ephemeral.customType, "agentmemory-context");
    assert.equal(JSON.parse(ephemeral.content).trust, "untrusted-reference-data");
    assert.equal(context.messages[1], originalMessages[0]);

    const continuation = mock.handlers.get("context")({
      messages: [
        originalMessages[0],
        { role: "assistant", content: [{ type: "toolCall", name: "read" }], timestamp: 2 },
        { role: "toolResult", content: [{ type: "text", text: "tool output" }], timestamp: 3 },
      ],
    });
    assert.equal(continuation.messages[0].customType, "agentmemory-context");
    assert.equal(continuation.messages[1], originalMessages[0]);
    assert.equal(continuation.messages.at(-1).role, "toolResult");

    mock.handlers.get("agent_end")({
      messages: [{
        role: "assistant",
        stopReason: "error",
        content: [{ type: "text", text: "A failed partial result that must never be retained." }],
      }],
    });
    assert.equal(observeCount, 0);
    mock.handlers.get("agent_end")({
      messages: [{
        role: "assistant",
        stopReason: "stop",
        content: [{
          type: "text",
          text: "The final implementation uses scoped, ephemeral recall and records only one settled outcome.",
        }],
      }],
    });
    await mock.handlers.get("agent_settled")({}, ctx);
    assert.equal(observeCount, 1);
    const observe = requests.find((item) => item.path === "/agentmemory/observe");
    assert.match(observe.body.data.tool_input, /^Outcome:/);

    await mock.commands.get("agentmemory-private").handler("do not use memory for this prompt", ctx);
    assert.equal(mock.sentMessages.length, 1);
    assert.equal(mock.sentMessages[0].message.customType, "agentmemory-private-prompt");
    assert.equal(mock.sentMessages[0].options.triggerTurn, true);
    const privateContext = mock.handlers.get("context")({
      messages: [{
        content: "stale persisted memory",
        customType: "agentmemory-context",
        display: false,
        role: "custom",
        timestamp: 1,
      }],
    });
    assert.deepEqual(privateContext.messages, []);
    await assert.rejects(
      mock.tools.get("memory_search").execute("tool-1", { query: "anything" }, undefined, undefined, ctx),
      /disabled for this private run/,
    );
    mock.handlers.get("agent_end")({
      messages: [{ role: "assistant", stopReason: "stop", content: "private result" }],
    });
    await mock.handlers.get("agent_settled")({}, ctx);
    assert.equal(observeCount, 1);

    healthStatus = "degraded";
    await assert.rejects(
      mock.tools.get("memory_health").execute("tool-2", {}, undefined, undefined, ctx),
      /reports degraded/,
    );
    healthStatus = "healthy";
    const health = await mock.tools.get("memory_health").execute(
      "tool-3",
      {},
      undefined,
      undefined,
      ctx,
    );
    assert.equal(health.details.ok, true);

    await assert.rejects(
      mock.tools.get("memory_save").execute(
        "tool-4",
        { concepts: ["DB_PASSWORD=swordfish"], content: "A safe-looking fact" },
        undefined,
        undefined,
        ctx,
      ),
      /credential-like/,
    );
    await assert.rejects(
      mock.tools.get("memory_save").execute(
        "tool-5",
        { content: "A valid fact", files: ["/absolute/path"] },
        undefined,
        undefined,
        ctx,
      ),
      /repository-relative/,
    );
    const saved = await mock.tools.get("memory_save").execute(
      "tool-6",
      {
        concepts: ["deployment"],
        content: "Use the shared stack preparation path for application redeploys.",
        files: ["scripts/deploy-stack.sh"],
        ttlDays: 30,
        type: "workflow",
      },
      undefined,
      undefined,
      ctx,
    );
    assert.equal(saved.details.id, "mem_saved");
    assert.equal(rememberCount, 1);
    const remember = requests.find((item) => item.path === "/agentmemory/remember");
    assert.equal(remember.body.project, activeProject);
    assert.equal(remember.body.concepts[0], `${activeProject}::deployment`);

    await mock.handlers.get("session_shutdown")({}, ctx);
    assert.ok(statuses.some((item) => item.value.includes("agentmemory")));
    assert.ok(notifications.every((item) => !item.message.includes("lifecycle-test-secret")));
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    await server.close();
  }
});
