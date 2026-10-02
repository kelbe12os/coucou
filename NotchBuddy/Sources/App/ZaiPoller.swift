import Foundation
import SwiftUI

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
        guard let key = KeychainStore.shared.get("zai-api-key"), !key.isEmpty else { return }
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
