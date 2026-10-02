import Foundation
import SwiftUI

/// Where the Z.ai coding-plan key comes from. No Keychain on purpose: an ad-hoc signed app changes
/// identity on every rebuild, so a Keychain item would prompt for access again and again.
/// Order: a key saved from Coucou's Settings (file, mode 0600) wins; otherwise pi's own provider
/// config, which the user maintains anyway for the glm workers.
enum ZaiKey {
    static var fileURL: URL { HookServer.supportDir.appendingPathComponent("zai-api-key") }
    static var piConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent/models.json")
    }

    /// (key, human-readable source) or nil when nothing usable exists.
    static func resolve() -> (key: String, source: String)? {
        if let s = try? String(contentsOf: fileURL, encoding: .utf8) {
            let k = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty { return (k, "saved in Coucou") }
        }
        if let data = try? Data(contentsOf: piConfigURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let providers = json["providers"] as? [String: Any],
           let zai = providers["zai"] as? [String: Any],
           let k = zai["apiKey"] as? String, !k.isEmpty, !k.hasPrefix("env:") {
            return (k, "pi config (~/.pi/agent/models.json)")
        }
        return nil
    }

    static func save(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { clear(); return }
        try? FileManager.default.createDirectory(at: HookServer.supportDir, withIntermediateDirectories: true)
        try? k.write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o600 as NSNumber], ofItemAtPath: fileURL.path)
    }

    static func clear() { try? FileManager.default.removeItem(at: fileURL) }
}

/// Polls the Z.ai GLM coding-plan quota (5-hour and weekly windows) for the usage card.
final class ZaiPoller: @unchecked Sendable {
    static let shared = ZaiPoller()
    private var timer: DispatchSourceTimer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + 4, repeating: 60)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func pollNow() { poll() }

    private func poll() {
        guard let key = ZaiKey.resolve()?.key else { return }
        fetchQuota(key: key)
    }

    private func fetchQuota(key: String) {
        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

        URLSession.shared.dataTask(with: req) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                let errMsg = code == 0 ? (error?.localizedDescription ?? "Z.ai no connection") : "Zai \(code)"
                DispatchQueue.main.async { AppState.shared.zaiUsage.error = errMsg }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = json["data"] as? [String: Any] else { return }

            var fiveHourPct: Int? = nil
            var fiveHourResetsAt: Date? = nil
            var weeklyPct: Int? = nil
            var weeklyResetsAt: Date? = nil
            let level = d["level"] as? String
            if let limits = d["limits"] as? [[String: Any]] {
                for l in limits {
                    let unit = (l["unit"] as? NSNumber)?.intValue ?? 0
                    let pct = (l["percentage"] as? NSNumber)?.intValue
                    let reset = (l["nextResetTime"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
                    if unit == 3 { fiveHourPct = pct; fiveHourResetsAt = reset }
                    if unit == 6 { weeklyPct = pct; weeklyResetsAt = reset }
                }
            }

            let fh = fiveHourPct, fr = fiveHourResetsAt
            let wk = weeklyPct, wr = weeklyResetsAt
            let lv = level ?? ""
            DispatchQueue.main.async {
                let state = AppState.shared
                let prev = state.zaiUsage
                var u = prev
                u.fiveHourPct = fh
                u.fiveHourResetsAt = fr
                u.weeklyPct = wk
                u.weeklyResetsAt = wr
                u.level = lv.isEmpty ? nil : lv
                u.error = nil
                u.updatedAt = Date()
                state.zaiUsage = u
                appendAppLog("nb.log", "Zai 5h=\(fh.map(String.init) ?? "-") wk=\(wk.map(String.init) ?? "-") level=\(lv.isEmpty ? "-" : lv)")
                func up(_ a: Int?, _ b: Int?) -> Bool { (a ?? 0) < 90 && (b ?? 0) >= 90 }
                if up(prev.fiveHourPct, fh) || up(prev.weeklyPct, wk) { SoundEngine.shared.play("rate") }
            }
        }.resume()
    }
}
