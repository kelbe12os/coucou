# Brief: HTTP relay so remote Claude Code sessions reach the notch

## Task
Claude Code sessions on another machine (a Windows PC on the user's tailnet) fire their hooks
there, where Coucou's Unix socket does not exist. Add an HTTP listener to Coucou that accepts
the same JSON lines the socket accepts and bridges each request to the socket, so every feature
carries over unchanged, including the blocking permission request. Tag remote sessions with
their host. Give Settings a box to enable it, show the token and addresses, and test it. The
remote-side scripts are written by the coordinator; you build only the app side. Build, in order:
1. `AppState.swift` — two persisted settings (D1).
2. `RelayServer.swift` (new, Appendix F, create verbatim) — the listener and bridge.
3. `HookServer.swift` — accept the `remote` terminal token; host tag in project names (D3).
4. `SettingsView.swift` — "Remote sessions" box (D4).
5. `AppDelegate.swift` — start the relay when enabled (D5).
6. `xcodegen`, then build.

Fully implemented, no stubs, no TODOs.
Rules: write each file as soon as it is drafted; build after step 2 and at the end; at most two
attempts per compile error; an error you cannot fix in two attempts is left and explained in the
report. Do not commit anywhere. The coordinator reviews and commits.
Environment rule: do not create, recreate, stop, start or reconfigure any container, and do not
change any port. If the environment is not as described below, stop and ask.
Working-tree rule: never run git stash, reset, checkout, switch, clean or rebase, in either git
repository. If you need to compare with HEAD, use git diff or git show.
Machine rule: never run `claude`, `pi`, `curl`, `nc`, `tailscale`, `scripts/build.sh`,
`codesign`, `ditto`, `sudo`, `open`; never write under `~/.claude`, `~/.pi`, `~/Library` or
`/Applications`; never launch the app, never connect to its socket, never open a listening
port yourself. `xcodegen` and `xcodebuild` are allowed exactly as written under "Build and test
commands".
Context rule: pipe build output through the grep given below; read only the region of a file you
need; never print a whole file.

## No discovery
Everything you need is in this brief. Do not run orientation commands (`git log`, `git status`,
`ls`, `find`, `tree`) and do not open, `cat`, `grep` or `read` any file region that appears in
the appendices: they are the current contents. The only files you may open are listed under
"Files you may read". If you believe you need anything else, ask; do not go looking.

## Scope
Allowed to change (all inside the nested checkout `build/coucou`, branch `orca`):
- `build/coucou/NotchBuddy/Sources/App/AppState.swift` (additions only, D1)
- `build/coucou/NotchBuddy/Sources/App/RelayServer.swift` (new)
- `build/coucou/NotchBuddy/Sources/App/HookServer.swift` (the two regions in Appendix B only)
- `build/coucou/NotchBuddy/Sources/App/SettingsView.swift` (the regions in Appendix D only)
- `build/coucou/NotchBuddy/Sources/App/AppDelegate.swift` (one line, D5)
- `docs/briefs/04-remote-relay-report.md` (new; your report, in the outer repo)
Not allowed: anything else. `xcodegen` regenerating `NotchBuddy.xcodeproj` is expected.

## Files you may read (not embedded)
- `build/coucou/NotchBuddy/Sources/App/ClaudeCodeCLI.swift` — the `execute` function, only if
  you need the `Process` pattern for D4's Tailscale lookup.
Nothing else.

## Build and test commands (only these)
```
cd build/coucou/NotchBuddy && xcodegen 2>&1 | tail -n 3
cd build/coucou/NotchBuddy && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' | head -n 40
```
Run `xcodegen` once after creating the new file. No unit tests exist; a clean
`** BUILD SUCCEEDED **` with zero `error:` lines is the acceptance criterion.

## Environment
- macOS, Apple silicon, Xcode 27.0, `xcodegen` on PATH. Swift 6, `-strict-concurrency=complete`.
  `AppState`, the views and `HookServer`'s event methods are `@MainActor`. The Network framework
  (`import Network`) is available; the deployment target is macOS 15.
- Outer repo `~/Workspaces/Code/coucou-orca`; nested checkout `build/coucou` on
  branch `orca` with the fork's patch applied (Orca panes, chat via Claude Code, pi pills, usage
  card). The app is installed and running on this Mac; you do not touch it.
- The socket protocol you bridge to (verified from the code, Appendix B): a client connects to
  `HookServer.socketPath`, sends one JSON object terminated by `\n`, and reads one JSON line
  back. For every event except `PermissionRequest` the reply is `{"ok":true}` immediately. For
  `PermissionRequest` the reply arrives when the user clicks, as
  `{"permissionDecision":"allow"|"always"|"deny"|"ask"}`, or `"ask"` after 115 s. The server
  reads with a 5 s receive timeout, so the request line must be sent at once.
- The remote relay the coordinator writes sends `"term_program":"remote"`, `"bundle_id":"remote"`
  and `"remote_host":"<lowercase hostname>"` inside the payload, plus Claude Code's own fields.

## Design (binding)

### D1. AppState
After the usage block added by brief 03 (search for `var usageConfigured: Bool`), add:
```swift
    // MARK: - Remote relay (HTTP bridge for Claude Code sessions on other machines)
    @Published var relayEnabled: Bool = false {
        didSet { UserDefaults.standard.set(relayEnabled, forKey: "relayEnabled") }
    }
    @Published var relayPort: Int = 6771 {
        didSet { UserDefaults.standard.set(relayPort, forKey: "relayPort") }
    }
```
In `private init()`, after the `claudeUsage` restore lines, add:
```swift
        if let v = ud.object(forKey: "relayEnabled") as? Bool { relayEnabled = v }
        if let v = ud.object(forKey: "relayPort") as? Int, (1024...65535).contains(v) { relayPort = v }
```

### D2. RelayServer.swift
Create verbatim from Appendix F. Do not restructure it. If the compiler objects to a line, fix
the smallest thing that satisfies it and list the change under deviations.

### D3. HookServer
Two edits (Appendix B shows both regions):
- `supportedTerminalTokens`: add `"remote"` at the end of the array.
- Host tag: in **both** `processEvent` and `processPermissionRequest`, right after the line
  `let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)`, change
  `let` to `var` and append:
  ```swift
        if let host = payload["remote_host"] as? String, !host.isEmpty {
            projectName += " @ " + host
        }
  ```

### D4. SettingsView
New state: `@State private var relayToken: String = RelayServer.token()`,
`@State private var relayTailnetName: String = ""`, `@State private var relayTestResult: String = ""`,
`@State private var relayPortText: String = String(AppState.shared.relayPort)`.
Insert a new `GroupBox("Remote sessions")` **right after** the `GroupBox("Usage card")` block
(Appendix D1 shows where that block ends and the next one starts):
```swift
                GroupBox("Remote sessions") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Claude Code sessions on other machines reach the notch through this relay. Each event is forwarded to Coucou over HTTP with a token; approvals work the same as local ones.")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                        Toggle("Enable relay", isOn: $state.relayEnabled)
                            .onChange(of: state.relayEnabled) { _, on in
                                if on { RelayServer.shared.start(port: UInt16(state.relayPort)) } else { RelayServer.shared.stop() }
                                relayTestResult = ""
                            }
                        HStack(spacing: 8) {
                            Text("Port").font(.system(size: 12))
                            TextField("6771", text: $relayPortText)
                                .textFieldStyle(.roundedBorder).frame(width: 80)
                                .onSubmit { applyRelayPort() }
                            Button("Apply") { applyRelayPort() }
                        }
                        HStack(spacing: 8) {
                            Text("Token").font(.system(size: 12))
                            Text(relayToken).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(relayToken, forType: .string)
                                statusMessage = "✓ Token copied."
                            }
                            Button("Regenerate") {
                                relayToken = RelayServer.regenerateToken()
                                statusMessage = "✓ New token. Update the remote machines."
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This Mac on the LAN: \(ProcessInfo.processInfo.hostName)")
                                .font(.system(size: 11, design: .monospaced))
                            Text("On the tailnet: \(relayTailnetName.isEmpty ? "looking up…" : relayTailnetName)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        HStack(spacing: 10) {
                            Button("Test") { testRelay() }
                            if !relayTestResult.isEmpty {
                                Text(relayTestResult).font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                        Text("Remote install: scripts/remote/ in the coucou-orca repo. Point it at one of the names above, this port and the token.")
                            .font(.system(size: 10.5)).foregroundColor(.secondary)
                    }
                    .padding(6)
                }
                .task { lookupTailnetName() }
```
Helpers in the view:
```swift
    private func applyRelayPort() {
        guard let p = Int(relayPortText), (1024...65535).contains(p) else {
            statusMessage = "❌ Port must be between 1024 and 65535."; return
        }
        state.relayPort = p
        if state.relayEnabled { RelayServer.shared.restart(port: UInt16(p)) }
        statusMessage = "✓ Relay port set to \(p)."
    }

    private func testRelay() {
        guard state.relayEnabled else { relayTestResult = "relay is off"; return }
        let port = state.relayPort
        let token = relayToken
        relayTestResult = "testing…"
        Task {
            guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return }
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                relayTestResult = code == 200 ? "ok: \(String(data: data, encoding: .utf8) ?? "")" : "HTTP \(code)"
            } catch {
                relayTestResult = "failed: \(error.localizedDescription)"
            }
        }
    }

    private func lookupTailnetName() {
        Task.detached {
            let name = RelayServer.tailnetName() ?? "Tailscale not running or CLI not found"
            await MainActor.run { relayTailnetName = name }
        }
    }
```

### D5. AppDelegate
In `setupIsland()`, after `ZaiPoller.shared.start()`, add:
```swift
        if AppState.shared.relayEnabled { RelayServer.shared.start(port: UInt16(AppState.shared.relayPort)) }
```

### D6. Behaviour the code must have (restating Appendix F so the review can check it)
- Listens on all interfaces on the configured TCP port only while enabled; a bind failure logs
  `Relay: cannot listen on <port>` and leaves the app otherwise working.
- Every request needs `Authorization: Bearer <token>`; otherwise `401` and a log line.
- `GET /health` → `200 {"ok":true,"app":"coucou"}`.
- `POST /hook` with a JSON object body → the body is written to the Unix socket as one line and
  the socket's reply line is returned as the HTTP body with `200`. If Coucou's socket is not
  reachable → `502`. If no reply within 122 s → `504` with `{"permissionDecision":"ask"}` so a
  remote permission prompt falls back to the terminal.
- Body limit 1 MB, header read limit 64 KB, 15 s to receive a request, 32 concurrent
  connections; anything over is dropped.
- One log line on start (`Relay listening on port N`) and on each rejected request; none per
  successful event (the hook server already logs those).

## Tests
No test target. Acceptance is a green build. The coordinator verifies after install: `Test` in
Settings returns ok, a sample event posted with `curl` from this Mac shows in `nb.log`, and a
posted `PermissionRequest` holds until a click. You do not run any of that.

## Docs (in scope)
Only your report.

## Self-verify before reporting done
1. Run the two build commands. Quote the final `BUILD SUCCEEDED` line.
2. `git -C build/coucou status --short` and `git -C build/coucou diff --stat`: only the five
   Swift files (one new) and the regenerated `.xcodeproj`. Outer repo: only your report.
3. Write `docs/briefs/04-remote-relay-report.md`: build outcome, files touched with line counts,
   out-of-scope changes at the top if any (section titled **⚠️ Out-of-scope changes — review
   required**), numbered deviations with reasons, per-error attempt accounting. Summarise in the
   `worker_done` body and set `--report-path docs/briefs/04-remote-relay-report.md`.

## If anything is unclear
Ask with `orca orchestration ask --question "<question>" --timeout-ms 1800000`. If it times out,
run `orca orchestration ask --resume <message_id>`. Never guess on: the HTTP status codes, the
auth check, the socket line protocol, the timeouts, anything that would make you run the app or
open a port. Guess freely on: private helper names, paddings, label wording.

## Communication protocol
1. Plan gate (blocking). Within two minutes of starting, from the Scope and Design sections and
   before opening anything else, send your plan and wait for approval:
   `orca orchestration ask --question "PLAN: <files you will create or modify, one line each;
   open questions>" --options "approve,revise" --timeout-ms 1800000`
   If the answer is "revise", the reply body contains the changes; re-plan and ask again.
   On timeout: `orca orchestration ask --resume <message_id>`. Never proceed unapproved.
2. Notes (non-blocking). Send a status message and keep working:
   `orca orchestration send --type status --subject "<one line>" --body "<details>"
   --task-id <task_id> --dispatch-id <dispatch_id>`
   at: the first file landed; all files on disk; every deviation from this brief, at the moment
   you decide it, with the reason; first green build; after any second attempt on an error.
3. Inbox (pull). Before each phase change (plan → implement → build → report), and before you
   diagnose any build error, run
   `orca orchestration check --terminal <your handle> --unread --format` and apply any
   coordinator guidance you find before continuing.
4. Questions. Whenever this brief contradicts itself or the code, ask. Do not guess.
5. Heartbeat every 5 minutes with `--phase`; `worker_done` exactly once, as the injected
   preamble says, with `--outcome succeeded` or `--outcome failed`.

## Appendix A: AppState.swift, the anchor (end of the brief-03 usage block)
```swift
    /// True when the right panel should carry the usage card or strip.
    var usageConfigured: Bool {
        HookServer.statusLineRelayInstalled()
            || ZaiKey.resolve() != nil
            || claudeUsage.updatedAt != nil
            || zaiUsage.updatedAt != nil
    }
```
and in `init`, the lines you add after:
```swift
        if let d = ud.data(forKey: "claudeUsage"),
           let u = try? JSONDecoder().decode(ClaudeUsage.self, from: d) { claudeUsage = u }
```

## Appendix B: HookServer.swift regions
B1, the allowlist (search for it; line ≈ 341):
```swift
    private static let supportedTerminalTokens = ["vscode", "orca", "com.stablyai.orca", "ghostty"]
```
B2, the two `projectName` lines, one in `processEvent` (≈ line 167) and one in
`processPermissionRequest` (≈ line 384). Both read exactly:
```swift
        let rawName = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)
```
B3, protocol facts (unchanged code, for orientation): `static var socketPath: String` and
`static var supportDir: URL` exist on `HookServer`; the client handler reads one `\n`-terminated
JSON object, replies with `sendLine(fd:text:)` and closes; `PermissionRequest` keeps the fd open
and replies `{"permissionDecision":"…"}` from `sendApprovalDecision(_:)` or after a 115 s timer.
`appendAppLog("nb.log", _:)` is the free logging function available everywhere.

## Appendix C: not used

## Appendix D: SettingsView.swift anchors
D1: the `GroupBox("Usage card") { … }` block starts at ≈ line 306 and ends with
```swift
                    .padding(6)
                }

                // MARK: Gemini CLI
```
(the Gemini box follows). Insert the new box between them. The `@State` block is at the top of
the view (≈ lines 27–40); `statusMessage` and `state` exist. `import AppKit` is present, so
`NSPasteboard` is available.

## Appendix E: AppDelegate.swift, the anchor
```swift
        NotionPoller.shared.start()
        ZaiPoller.shared.start()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
```

## Appendix F: RelayServer.swift, create verbatim
```swift
import Foundation
import Network
import Security

/// HTTP bridge for Claude Code sessions on other machines. A remote hook relay POSTs the same
/// JSON object the local Unix socket accepts; this server forwards it to the socket and returns
/// the socket's reply, so approvals block and resolve exactly like local ones.
final class RelayServer: @unchecked Sendable {
    static let shared = RelayServer()

    private let queue = DispatchQueue(label: "coucou.relay", qos: .userInitiated)
    private var listener: NWListener?
    private var active = 0

    private static let maxActive = 32
    private static let maxHeader = 65_536
    private static let maxBody = 1_048_576
    private static let requestTimeout: TimeInterval = 15
    private static let bridgeTimeout: TimeInterval = 122

    private init() {}

    // MARK: - Token

    static var tokenURL: URL { HookServer.supportDir.appendingPathComponent("relay-token") }

    static func token() -> String {
        if let t = try? String(contentsOf: tokenURL, encoding: .utf8) {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 16 { return trimmed }
        }
        return regenerateToken()
    }

    @discardableResult
    static func regenerateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let t = bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(at: HookServer.supportDir, withIntermediateDirectories: true)
        try? t.write(to: tokenURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o600 as NSNumber], ofItemAtPath: tokenURL.path)
        return t
    }

    /// The Mac's MagicDNS name from the Tailscale CLI, if installed and running. Blocking; call off the main actor.
    static func tailnetName() -> String? {
        let candidates = ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale",
                          "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
        guard let bin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["status", "--json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let me = json["Self"] as? [String: Any],
              let dns = me["DNSName"] as? String, !dns.isEmpty else { return nil }
        let state = json["BackendState"] as? String ?? ""
        let name = dns.hasSuffix(".") ? String(dns.dropLast()) : dns
        return state == "Running" ? name : name + " (Tailscale stopped)"
    }

    // MARK: - Lifecycle

    func start(port: UInt16) { queue.async { self.startLocked(port: port) } }
    func stop() { queue.async { self.listener?.cancel(); self.listener = nil } }
    func restart(port: UInt16) { queue.async { self.listener?.cancel(); self.listener = nil; self.startLocked(port: port) } }

    private func startLocked(port: UInt16) {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: nwPort) else {
            appendAppLog("nb.log", "Relay: cannot listen on \(port)")
            return
        }
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: appendAppLog("nb.log", "Relay listening on port \(port)")
            case .failed(let err): appendAppLog("nb.log", "Relay failed: \(err)")
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.start(queue: queue)
        listener = l
    }

    // MARK: - Connections

    private final class Request: @unchecked Sendable {
        var buffer = Data()
        var headerEnd: Int? = nil
        var method = ""
        var path = ""
        var headers: [String: String] = [:]
        var contentLength = 0
        var finished = false
        var released = false
    }

    private func accept(_ conn: NWConnection) {
        guard active < Self.maxActive else { conn.cancel(); return }
        active += 1
        let req = Request()
        conn.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.release(req) }
            if case .failed = state { conn.cancel() }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak self] in
            guard let self, !req.finished else { return }
            req.finished = true
            self.respond(conn, 408, #"{"error":"request timeout"}"#)
        }
        receive(conn, req)
    }

    private func release(_ req: Request) {
        guard !req.released else { return }
        req.released = true
        active = max(0, active - 1)
    }

    private func receive(_ conn: NWConnection, _ req: Request) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, !req.finished else { return }
            if let data { req.buffer.append(data) }
            if error != nil { req.finished = true; conn.cancel(); return }
            if req.headerEnd == nil {
                if let range = req.buffer.range(of: Data("\r\n\r\n".utf8)) {
                    req.headerEnd = range.upperBound
                    guard self.parseHead(req) else {
                        req.finished = true
                        self.respond(conn, 400, #"{"error":"bad request"}"#)
                        return
                    }
                } else if req.buffer.count > Self.maxHeader {
                    req.finished = true
                    self.respond(conn, 431, #"{"error":"headers too large"}"#)
                    return
                }
            }
            if let end = req.headerEnd {
                if req.contentLength > Self.maxBody {
                    req.finished = true
                    self.respond(conn, 413, #"{"error":"body too large"}"#)
                    return
                }
                if req.buffer.count - end >= req.contentLength {
                    req.finished = true
                    let body = req.buffer.subdata(in: end..<(end + req.contentLength))
                    self.route(conn, req, body: body)
                    return
                }
            }
            if isComplete { req.finished = true; conn.cancel(); return }
            self.receive(conn, req)
        }
    }

    private func parseHead(_ req: Request) -> Bool {
        guard let end = req.headerEnd,
              let head = String(data: req.buffer.prefix(end), encoding: .utf8) else { return false }
        let lines = head.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let requestLine = lines.first else { return false }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return false }
        req.method = String(parts[0]).uppercased()
        req.path = String(parts[1])
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            req.headers[name] = value
        }
        req.contentLength = Int(req.headers["content-length"] ?? "0") ?? 0
        return true
    }

    // MARK: - Routing

    private func route(_ conn: NWConnection, _ req: Request, body: Data) {
        let auth = req.headers["authorization"] ?? ""
        guard auth == "Bearer \(Self.token())" else {
            appendAppLog("nb.log", "Relay: rejected \(req.method) \(req.path) (bad token)")
            respond(conn, 401, #"{"error":"unauthorized"}"#)
            return
        }
        switch (req.method, req.path) {
        case ("GET", "/health"):
            respond(conn, 200, #"{"ok":true,"app":"coucou"}"#)
        case ("POST", "/hook"):
            guard let obj = try? JSONSerialization.jsonObject(with: body), obj is [String: Any] else {
                appendAppLog("nb.log", "Relay: rejected POST /hook (not a JSON object)")
                respond(conn, 400, #"{"error":"body must be a JSON object"}"#)
                return
            }
            bridge(body, to: conn)
        default:
            respond(conn, 404, #"{"error":"not found"}"#)
        }
    }

    // MARK: - Bridge to the Unix socket

    private final class Flag: @unchecked Sendable { var done = false }

    private func bridge(_ body: Data, to conn: NWConnection) {
        let sock = NWConnection(to: .unix(path: HookServer.socketPath), using: .tcp)
        let flag = Flag()
        let timeout = DispatchWorkItem { [weak self] in
            guard !flag.done else { return }
            flag.done = true
            sock.cancel()
            self?.respond(conn, 504, #"{"permissionDecision":"ask","error":"timeout"}"#)
        }
        queue.asyncAfter(deadline: .now() + Self.bridgeTimeout, execute: timeout)

        sock.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                var line = body
                line.append(0x0A)
                sock.send(content: line, completion: .contentProcessed { err in
                    if err != nil, !flag.done {
                        flag.done = true; timeout.cancel(); sock.cancel()
                        self.respond(conn, 502, #"{"error":"socket write failed"}"#)
                        return
                    }
                    self.readLine(sock, Data()) { reply in
                        guard !flag.done else { return }
                        flag.done = true; timeout.cancel(); sock.cancel()
                        self.respond(conn, 200, reply ?? #"{"ok":true}"#)
                    }
                })
            case .failed, .waiting:
                guard !flag.done else { return }
                flag.done = true; timeout.cancel(); sock.cancel()
                self.respond(conn, 502, #"{"error":"coucou socket unavailable"}"#)
            default:
                break
            }
        }
        sock.start(queue: queue)
    }

    private func readLine(_ sock: NWConnection, _ acc: Data, _ done: @escaping @Sendable (String?) -> Void) {
        sock.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            var acc = acc
            if let data { acc.append(data) }
            if let nl = acc.firstIndex(of: 0x0A) {
                done(String(data: acc.prefix(upTo: nl), encoding: .utf8))
                return
            }
            if error != nil || isComplete {
                done(acc.isEmpty ? nil : String(data: acc, encoding: .utf8))
                return
            }
            self?.readLine(sock, acc, done)
        }
    }

    // MARK: - Response

    private func respond(_ conn: NWConnection, _ status: Int, _ body: String) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 408: reason = "Request Timeout"
        case 413: reason = "Payload Too Large"
        case 431: reason = "Request Header Fields Too Large"
        case 502: reason = "Bad Gateway"
        case 504: reason = "Gateway Timeout"
        default:  reason = "Error"
        }
        let bodyData = Data(body.utf8)
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(bodyData.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(bodyData)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}
```
