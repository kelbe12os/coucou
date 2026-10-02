import Foundation

/// Runs the locally installed Claude Code CLI in headless mode (`claude -p`) so the chat uses the
/// user's Claude Code login instead of an API key. Everything here is nonisolated and Sendable;
/// callers are @MainActor and await the result.
enum ClaudeCodeCLI {

    struct Output: Sendable {
        let text: String
        let sessionId: String?
        let isError: Bool
    }

    /// Model choices offered in the picker and in Settings. "default" means: do not pass --model,
    /// so Claude Code uses whatever the user configured for the CLI itself.
    static let modelChoices: [(id: String, label: String)] = [
        ("opus",    "Opus"),
        ("sonnet",  "Sonnet"),
        ("haiku",   "Haiku"),
        ("default", "Default (your Claude Code setting)"),
    ]

    /// First executable `claude` found. $COUCOU_CLAUDE_BIN wins; then the usual install paths.
    static func locate() -> String? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        if let p = env["COUCOU_CLAUDE_BIN"], fm.isExecutableFile(atPath: p) { return p }
        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.npm-global/bin/claude",
        ]
        if let nodes = try? fm.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            candidates += nodes.sorted().reversed().map { "\(home)/.nvm/versions/node/\($0)/bin/claude" }
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// `claude --version`, first line, or nil when the binary is missing or does not answer in 10 s.
    static func version() async -> String? {
        guard let bin = locate() else { return nil }
        guard let r = try? await execute(bin: bin, args: ["--version"], cwd: nil, timeout: 10) else { return nil }
        return r.stdout.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    /// One headless turn. Pass `resumeSessionId` to continue a conversation.
    static func run(prompt: String, systemPrompt: String, model: String?, resumeSessionId: String?,
                    addDirs: [String], cwd: String?, timeout: TimeInterval = 120) async throws -> Output {
        guard let bin = locate() else {
            throw failure("Claude Code CLI not found. Install Claude Code, or set COUCOU_CLAUDE_BIN.")
        }
        var args = ["-p", prompt,
                    "--output-format", "json",
                    "--allowedTools", "WebSearch,WebFetch,Read",
                    "--append-system-prompt", systemPrompt]
        if let m = model, !m.isEmpty, m != "default" { args += ["--model", m] }
        if let s = resumeSessionId, !s.isEmpty { args += ["--resume", s] }
        for d in addDirs { args += ["--add-dir", d] }

        let r = try await execute(bin: bin, args: args, cwd: cwd, timeout: timeout)
        if r.timedOut {
            throw failure("Claude Code did not answer within \(Int(timeout)) s.")
        }
        guard let data = r.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let tail = String((r.stderr.isEmpty ? r.stdout : r.stderr).suffix(300))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw failure(tail.isEmpty ? "Claude Code returned no output (exit \(r.status))." : tail)
        }
        let text = (json["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isError = (json["is_error"] as? Bool ?? false) || r.status != 0
        return Output(text: text, sessionId: json["session_id"] as? String, isError: isError)
    }

    // MARK: - Process plumbing

    private struct Exec: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    private static func execute(bin: String, args: [String], cwd: String?, timeout: TimeInterval) async throws -> Exec {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Exec, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: bin)
                p.arguments = args

                // The CLI finds its Keychain login through USER/LOGNAME and HOME; a GUI app has
                // them, but set them explicitly so a missing one can never show up as "Not logged in".
                var env = ProcessInfo.processInfo.environment
                if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
                if env["USER"] == nil { env["USER"] = NSUserName() }
                if env["LOGNAME"] == nil { env["LOGNAME"] = NSUserName() }
                let binDir = (bin as NSString).deletingLastPathComponent
                let basePath = [binDir, "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"].joined(separator: ":")
                env["PATH"] = env["PATH"].map { basePath + ":" + $0 } ?? basePath
                for k in env.keys where k.hasPrefix("CLAUDE_CODE_") { env.removeValue(forKey: k) }
                p.environment = env
                p.currentDirectoryURL = URL(fileURLWithPath: cwd ?? NSHomeDirectory())

                let outPipe = Pipe()
                let errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                p.standardInput = FileHandle.nullDevice

                do {
                    try p.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }

                let timedOut = DataBox()
                let killer = DispatchWorkItem {
                    if p.isRunning {
                        timedOut.data = Data([1])
                        p.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                // Drain stderr concurrently so a chatty child can never block on a full pipe.
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                let errHandle = errPipe.fileHandleForReading
                DispatchQueue.global().async {
                    errBox.data = errHandle.readDataToEndOfFile()
                    group.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                p.waitUntilExit()
                killer.cancel()

                cont.resume(returning: Exec(
                    status: p.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errBox.data, encoding: .utf8) ?? "",
                    timedOut: !timedOut.data.isEmpty))
            }
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ClaudeCodeCLI", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
