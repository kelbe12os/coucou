// Live test: fake Coucou socket + the real pi binary with the extension loaded in print mode.
import { createServer } from "net";
import { spawn } from "child_process";
import { unlinkSync } from "fs";

const SOCK = process.env.COUCOU_SOCKET!;
const EXT = process.argv[2];
const PROMPT = process.argv[3] || "Reply with exactly one word: pong";
const KILL_MS = Number(process.env.KILL_MS || 90000);
try { unlinkSync(SOCK); } catch {}

const received: any[] = [];
const server = createServer((c) => {
  let buf = "";
  c.on("data", (d) => { buf += d.toString(); });
  c.on("end", () => { for (const l of buf.split("\n")) if (l.trim()) { try { received.push(JSON.parse(l)); } catch {} } });
});
await new Promise<void>((r) => server.listen(SOCK, r));

const args = ["-e", EXT, "--no-session", ...(process.env.PI_TOOLS ? [] : ["--no-tools"]), ...(process.env.PI_MODEL ? ["--model", process.env.PI_MODEL] : []), "-p", PROMPT];
console.log("spawning: pi", args.join(" "));
const t0 = Date.now();
const child = spawn("pi", args, { env: { ...process.env, COUCOU_SOCKET: SOCK, TERM_PROGRAM: "Orca" }, stdio: ["ignore", "pipe", "pipe"] });
let out = "", err = "";
child.stdout.on("data", (d) => { out += d.toString(); });
child.stderr.on("data", (d) => { err += d.toString(); });
const killer = setTimeout(() => { console.log(`killing pi after ${KILL_MS} ms`); child.kill("SIGKILL"); }, KILL_MS);
const code: number | null = await new Promise((r) => child.on("exit", (c) => r(c)));
clearTimeout(killer);
await new Promise((r) => setTimeout(r, 300));
server.close();

console.log(`pi exit=${code} in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
console.log("stdout:", out.trim().slice(0, 300) || "(empty)");
if (err.trim()) console.log("stderr:", err.trim().slice(0, 600));
console.log(`\n${received.length} events received:`);
for (const p of received) {
  const extra = p.tool_name ? `  ${p.tool_name}` : p.prompt ? `  prompt=${p.prompt}` : p.message ? `  message=${p.message}` : "";
  console.log(`  ${p.hook_event_name.padEnd(18)} agent=${p.coucou_agent.padEnd(16)} sid=${String(p.session_id).slice(0, 10)} term=${p.term_program}${extra}`);
}
