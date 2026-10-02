// coucou-status.ts — pi extension that reports session activity to Coucou (notch companion).
//
// Install: copy to ~/.pi/agent/extensions/coucou-status.ts. pi loads it in every mode,
// including the `-p` print mode and the workers Orca dispatches. Nothing leaves the machine:
// events are written as JSON lines to Coucou's owner-only Unix socket, one connection at a
// time so they arrive in order. If Coucou is not running, each write fails silently within
// a few hundred milliseconds and pi is never blocked.
//
// What Coucou shows: one pill per agent tag. The tag is derived in this order:
//   1. $COUCOU_AGENT (explicit override)
//   2. the brief this worker was dispatched with: "pi-<NN-slug>" from the first prompt that
//      mentions docs/briefs/NN-slug.md (the subagent-brief convention)
//   3. the pi session name (--name)
//   4. "pi-<cwd basename>"
// Tags are lowercase a-z0-9- and at most 24 chars, which is what Coucou accepts.
//
// Subagent milestones (from the orca-subagent-coordinator protocol) are surfaced as steps:
//   heartbeat --phase X           → "phase · X"
//   send --type status            → "note · <subject>"
//   worker-done --outcome X       → finished card "worker_done · X"
//   write docs/briefs/*-report.md → "report written · <file>"
// A run that ends with a provider error shows the error card with the provider's message.
//
// Set COUCOU_DISABLE=1 to turn the extension off for one process.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SOCKET_PATH =
  process.env.COUCOU_SOCKET ||
  `${process.env.HOME || ""}/Library/Application Support/NotchBuddy/nb.sock`;
const SEND_TIMEOUT_MS = 300;
const MAX_TEXT = 160;

type Json = Record<string, unknown>;

// ---------- tag derivation ----------

function sanitizeTag(raw: string): string {
  const s = raw
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 24)
    .replace(/-+$/g, "");
  return s && s !== "claude" ? s : "";
}

function briefSlugFrom(text: string): string | undefined {
  // docs/briefs/03-auth-hooks.md  →  03-auth-hooks   (a -report.md is not a dispatch)
  const m = /docs\/briefs\/([a-z0-9][a-z0-9._-]*?)(?:-report)?\.md\b/i.exec(text);
  return m ? m[1] : undefined;
}

function clip(s: unknown, n = MAX_TEXT): string {
  const t = typeof s === "string" ? s : "";
  return t.length > n ? t.slice(0, n) : t;
}

// ---------- transport: one connection at a time, in order ----------

let chain: Promise<void> = Promise.resolve();

function writeOnce(line: string): Promise<void> {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => { if (!done) { done = true; resolve(); } };
    try {
      const net = require("net") as typeof import("net");
      const sock = net.createConnection({ path: SOCKET_PATH });
      const timer = setTimeout(() => { sock.destroy(); finish(); }, SEND_TIMEOUT_MS);
      sock.once("connect", () => sock.end(line));
      sock.once("close", () => { clearTimeout(timer); finish(); });
      sock.once("error", () => { clearTimeout(timer); sock.destroy(); finish(); });
    } catch {
      finish();
    }
  });
}

function send(payload: Json): Promise<void> {
  if (process.env.COUCOU_DISABLE === "1") return Promise.resolve();
  const line = JSON.stringify(payload) + "\n";
  chain = chain.then(() => writeOnce(line));
  return chain;
}

// ---------- tool mapping (pi names → the names Coucou labels) ----------

function mapTool(name: string, args: Json | undefined): { tool_name: string; tool_input: Json } {
  const a = args || {};
  switch (name) {
    case "bash":  return { tool_name: "Bash",  tool_input: { command: clip(a.command) } };
    case "read":  return { tool_name: "Read",  tool_input: { file_path: clip(a.path) } };
    case "write": return { tool_name: "Write", tool_input: { file_path: clip(a.path) } };
    case "edit":  return { tool_name: "Edit",  tool_input: { file_path: clip(a.path) } };
    case "grep":  return { tool_name: "Grep",  tool_input: { query: clip(a.pattern) } };
    case "find":  return { tool_name: "Glob",  tool_input: { query: clip(a.pattern) } };
    case "ls":    return { tool_name: "LS",    tool_input: { path: clip(a.path) || "." } };
    default:      return { tool_name: name,    tool_input: {} };
  }
}

// ---------- orchestration milestones from bash commands ----------

function milestoneFrom(command: string): { kind: "phase" | "note" | "done"; text: string } | undefined {
  if (!/\borca\s+orchestration\b/.test(command)) return undefined;
  if (/\bworker-done\b/.test(command)) {
    const m = /--outcome\s+["']?([a-z_-]+)/i.exec(command);
    return { kind: "done", text: `worker_done · ${m ? m[1] : "sent"}` };
  }
  const phase = /--phase\s+["']?([a-z_-]+)/i.exec(command);
  if (phase) return { kind: "phase", text: `phase · ${phase[1]}` };
  if (/--type\s+["']?status\b/.test(command)) {
    const subj = /--subject\s+(?:"([^"]*)"|'([^']*)'|(\S+))/.exec(command);
    const s = subj ? subj[1] || subj[2] || subj[3] : "";
    return { kind: "note", text: `note · ${clip(s, 60) || "status"}` };
  }
  return undefined;
}

// ---------- extension ----------

export default function (pi: ExtensionAPI) {
  let tag = sanitizeTag(process.env.COUCOU_AGENT || "");
  let sessionId = "";
  let cwd = process.cwd();
  let announced = false;
  let doneSent = false;     // worker_done milestone already produced the finished card
  let terminalSent = false; // one Stop/StopFailure per agent run
  let lastTerminal = { key: "", at: 0 }; // pi retries a failed request as new runs; collapse repeats

  function terminal(event: string, message: string): void {
    const key = `${event}|${message}`;
    const now = Date.now();
    if (key === lastTerminal.key && now - lastTerminal.at < 120_000) return;
    lastTerminal = { key, at: now };
    emit(event, { message });
  }

  const base = (): Json => ({
    coucou_agent: tag || "pi",
    session_id: sessionId || `pi-${process.pid}`,
    cwd,
    term_program: process.env.TERM_PROGRAM || "",
    bundle_id: process.env.__CFBundleIdentifier || "",
  });

  const emit = (event: string, extra: Json = {}) =>
    send({ hook_event_name: event, ...base(), ...extra });

  function refresh(ctx: any): void {
    try {
      cwd = ctx?.cwd || cwd;
      const sm = ctx?.sessionManager;
      if (sm?.getSessionId) sessionId = sm.getSessionId() || sessionId;
      if (!tag && sm?.getSessionName) {
        const n = sm.getSessionName();
        if (n) tag = sanitizeTag(`pi-${n}`);
      }
    } catch {
      /* ctx accessors can throw during session switches */
    }
  }

  function ensureTag(promptText?: string): void {
    const slug = promptText ? briefSlugFrom(promptText) : undefined;
    if (slug) { tag = sanitizeTag(`pi-${slug}`) || tag; return; }
    if (tag) return;
    const leaf = cwd.split("/").filter(Boolean).pop() || "";
    tag = sanitizeTag(`pi-${leaf}`) || "pi";
  }

  function announce(): void {
    if (announced) return;
    announced = true;
    emit("SessionStart");
  }

  pi.on("session_start", (_e: any, ctx: any) => {
    refresh(ctx);
    announced = false; doneSent = false; terminalSent = false;
    if (tag) announce(); // otherwise the first prompt names the brief and announces then
  });

  pi.on("agent_start", (_e: any, ctx: any) => {
    refresh(ctx);
    terminalSent = false;
  });

  pi.on("before_agent_start", (e: any, ctx: any) => {
    refresh(ctx);
    ensureTag(e?.prompt);
    announce();
    emit("UserPromptSubmit", { prompt: clip(e?.prompt, 60) });
  });

  pi.on("tool_execution_start", (e: any, ctx: any) => {
    refresh(ctx);
    if (doneSent) return;
    ensureTag();
    announce();
    const name = String(e?.toolName || "");
    emit("PreToolUse", mapTool(name, e?.args));

    if (name === "bash") {
      const m = milestoneFrom(String(e?.args?.command || ""));
      if (!m) return;
      if (m.kind === "done") {
        doneSent = true; terminalSent = true;
        terminal("Stop", m.text);
      } else {
        emit("PreToolUse", { tool_name: m.text, tool_input: {} });
      }
    } else if (name === "write" && /docs\/briefs\/[^/]*-report\.md$/.test(String(e?.args?.path || ""))) {
      emit("PreToolUse", { tool_name: `report written · ${String(e.args.path).split("/").pop()}`, tool_input: {} });
    }
  });

  pi.on("tool_execution_end", (e: any, ctx: any) => {
    refresh(ctx);
    if (doneSent) return;
    emit(e?.isError ? "PostToolUseFailure" : "PostToolUse", { tool_name: String(e?.toolName || "") });
  });

  pi.on("tool_approval_requested", (e: any, ctx: any) => {
    refresh(ctx);
    // A trailing "?" puts the pill in the question state; the approval itself stays in the pane.
    emit("Notification", { message: `${e?.toolName || "tool"} needs approval in the pane?` });
  });

  pi.on("agent_end", (e: any, ctx: any) => {
    refresh(ctx);
    if (terminalSent) return;
    terminalSent = true;
    let text = "", stop = "", err = "";
    try {
      const msgs = Array.isArray(e?.messages) ? e.messages : [];
      for (let i = msgs.length - 1; i >= 0; i--) {
        const m = msgs[i];
        if (m?.role !== "assistant") continue;
        stop = String(m.stopReason || "");
        err = String(m.errorMessage || "");
        if (Array.isArray(m.content)) {
          for (const c of m.content) if (c?.type === "text" && c.text) { text = c.text; break; }
        }
        break;
      }
    } catch { /* ignore */ }
    const oneLine = (s: string) => clip(s.replace(/\s+/g, " ").trim(), 60);
    if (stop === "error") { terminal("StopFailure", oneLine(err || text || "provider error")); return; }
    if (stop === "aborted") { terminal("Stop", "aborted"); return; }
    terminal("Stop", oneLine(text) || "turn finished");
  });

  pi.on("session_shutdown", async (_e: any, ctx: any) => {
    refresh(ctx);
    // pi awaits handlers, so draining here keeps SessionEnd after everything before it.
    await emit("SessionEnd");
  });
}
