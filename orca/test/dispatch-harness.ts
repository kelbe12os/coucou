// Test harness: fake Coucou socket server + fake pi ExtensionAPI firing a worker-like sequence.
import { createServer } from "net";
import { unlinkSync } from "fs";

const SOCK = process.env.COUCOU_SOCKET!;
try { unlinkSync(SOCK); } catch {}

const received: any[] = [];
const server = createServer((c) => {
  let buf = "";
  c.on("data", (d) => { buf += d.toString(); });
  c.on("end", () => { for (const l of buf.split("\n")) if (l.trim()) received.push(JSON.parse(l)); });
});
await new Promise<void>((r) => server.listen(SOCK, r));

const handlers: Record<string, Function[]> = {};
const fakePi = { on(ev: string, h: Function) { (handlers[ev] ||= []).push(h); return () => {}; } };
const fire = async (ev: string, e: any) => { for (const h of handlers[ev] || []) await h(e, ctx); await new Promise((r) => setTimeout(r, 40)); };

const ctx = { cwd: "/Users/example/Workspaces/project",
  sessionManager: { getSessionId: () => "sess-1234", getSessionName: () => undefined } };

const mod = await import(process.argv[2]);
mod.default(fakePi as any);

// A dispatch exactly like the coordinator skill's: Orca pastes the spec naming the brief.
await fire("session_start", { type: "session_start", reason: "startup" });
await fire("before_agent_start", { type: "before_agent_start", prompt: "Read docs/briefs/07-auth-hooks.md in full and execute it; it is the complete brief." });
await fire("tool_execution_start", { toolName: "read", args: { path: "docs/briefs/07-auth-hooks.md" } });
await fire("tool_execution_end", { toolName: "read", isError: false });
await fire("tool_execution_start", { toolName: "bash", args: { command: "orca orchestration send --type heartbeat --phase implementing --json" } });
await fire("tool_execution_end", { toolName: "bash", isError: false });
await fire("tool_execution_start", { toolName: "edit", args: { path: "src/auth/hooks.ts", edits: [] } });
await fire("tool_execution_end", { toolName: "edit", isError: false });
await fire("tool_execution_start", { toolName: "bash", args: { command: "npm test -- --run" } });
await fire("tool_execution_end", { toolName: "bash", isError: true });
await fire("tool_execution_start", { toolName: "bash", args: { command: 'orca orchestration send --type status --subject "all files on disk" --body "ready for review"' } });
await fire("tool_execution_end", { toolName: "bash", isError: false });
await fire("tool_approval_requested", { toolName: "bash", reason: "rm -rf", approvalMode: "ask" });
await fire("tool_execution_start", { toolName: "write", args: { path: "docs/briefs/07-auth-hooks-report.md", content: "# report" } });
await fire("tool_execution_end", { toolName: "write", isError: false });
await fire("message_end", { message: { role: "assistant", usage: { input: 1200, output: 800, cacheRead: 50000, cacheWrite: 0 } } });
await fire("message_end", { message: { role: "assistant", usage: { input: 1500, output: 2200, cacheRead: 62000, cacheWrite: 0 } } });
await fire("message_end", { message: { role: "user" } });
await fire("tool_execution_start", { toolName: "bash", args: { command: "orca orchestration worker-done --outcome succeeded --report-path docs/briefs/07-auth-hooks-report.md --json" } });
await fire("tool_execution_end", { toolName: "bash", isError: false });
await fire("agent_end", { messages: [{ role: "assistant", content: [{ type: "text", text: "Done. Report written." }] }] });
await fire("session_shutdown", { reason: "quit" });

await new Promise((r) => setTimeout(r, 200));
server.close();
for (const p of received) {
  const extra = p.tool_name ? `  ${p.tool_name}${p.tool_input?.command ? " · " + p.tool_input.command : p.tool_input?.file_path ? " · " + p.tool_input.file_path : p.tool_input?.query ? " · " + p.tool_input.query : ""}` : p.prompt ? `  prompt=${p.prompt}` : p.message ? `  message=${p.message}` : "";
  console.log(`${p.hook_event_name.padEnd(20)} agent=${p.coucou_agent.padEnd(18)}${extra}`);
}
console.log(`\n${received.length} events, tag=${received[0]?.coucou_agent}, tagLen=${received[0]?.coucou_agent.length}`);
const bad = received.filter((p) => !/^[a-z0-9-]{1,24}$/.test(p.coucou_agent) || p.coucou_agent === "claude");
console.log(bad.length ? `INVALID TAGS: ${bad.length}` : "all tags valid for Coucou");
const tok = received.find((p) => String(p.tool_name || "").startsWith("tokens ·"));
console.log(tok ? `tokens step: ${tok.tool_name}` : "TOKENS STEP MISSING");
