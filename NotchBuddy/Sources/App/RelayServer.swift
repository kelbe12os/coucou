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
    private final class TimeoutBox: @unchecked Sendable {
        let work: DispatchWorkItem
        init(_ work: DispatchWorkItem) { self.work = work }
    }

    private func bridge(_ body: Data, to conn: NWConnection) {
        let sock = NWConnection(to: .unix(path: HookServer.socketPath), using: .tcp)
        let flag = Flag()
        let timeout = DispatchWorkItem { [weak self] in
            guard !flag.done else { return }
            flag.done = true
            sock.cancel()
            self?.respond(conn, 504, #"{"permissionDecision":"ask","error":"timeout"}"#)
        }
        let timeoutBox = TimeoutBox(timeout)
        queue.asyncAfter(deadline: .now() + Self.bridgeTimeout, execute: timeout)

        sock.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                var line = body
                line.append(0x0A)
                sock.send(content: line, completion: .contentProcessed { err in
                    if err != nil, !flag.done {
                        flag.done = true; timeoutBox.work.cancel(); sock.cancel()
                        self.respond(conn, 502, #"{"error":"socket write failed"}"#)
                        return
                    }
                    self.readLine(sock, Data()) { reply in
                        guard !flag.done else { return }
                        flag.done = true; timeoutBox.work.cancel(); sock.cancel()
                        self.respond(conn, 200, reply ?? #"{"ok":true}"#)
                    }
                })
            case .failed, .waiting:
                guard !flag.done else { return }
                flag.done = true; timeoutBox.work.cancel(); sock.cancel()
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
