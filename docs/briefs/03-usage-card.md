# Brief: usage card for Claude and GLM in the right panel

## Task
Fill the island's right panel with a **usage card** showing two subscriptions side by side:
Claude Code's 5-hour and 7-day rate limits (from Claude Code's status-line JSON, relayed to
Coucou's socket) and the Z.ai GLM coding plan's 5-hour and weekly quota (polled from Z.ai).
When pi worker pills occupy the panel, the card folds into a one-line strip. When neither pills
nor usage exist, the panel disappears and the main card takes the full width. Build, in order:
1. `AppState.swift` — usage models and published fields (D1).
2. `HookServer.swift` — accept a `StatusLine` event, write the relay scripts, install/remove the
   status-line relay in `~/.claude/settings.json` (D2, Appendix F for the scripts).
3. `ZaiPoller.swift` (new) — poll Z.ai quota every 60 s (D3).
4. `ClaudeService.swift` — one Keychain key name (D4).
5. `UsageViews.swift` (new) — `UsageCardView` and `UsageStripView` (D5).
6. `IslandViewContent.swift` — right-panel logic, context % in the main card header, and the
   side-pill label fix (D6).
7. `SettingsView.swift` — "Usage card" box: relay install/remove and the Z.ai key (D7).
8. `AppDelegate.swift` — start the poller (D8).
9. `xcodegen`, then build.

Fully implemented, no stubs, no TODOs.
Rules: write each file as soon as it is drafted; build after step 2, after step 5 and at the end;
at most two attempts per compile error; an error you cannot fix in two attempts is left and
explained in the report. Do not commit anywhere. The coordinator reviews and commits.
Environment rule: do not create, recreate, stop, start or reconfigure any container, and do not
change any port. If the environment is not as described below, stop and ask.
Working-tree rule: never run git stash, reset, checkout, switch, clean or rebase, in either git
repository. If you need to compare with HEAD, use git diff or git show.
Machine rule: never run `claude`, `pi`, `curl`, `scripts/build.sh`, `codesign`, `ditto`, `sudo`,
`open`, and never write under `~/.claude`, `~/.pi`, `~/Library` or `/Applications`. Never
launch the app and never connect to its socket. `xcodegen` and `xcodebuild` are allowed exactly
as written under "Build and test commands". Your code may do those things when a human runs
the app later; you must not.
Context rule: pipe build output through the grep given below; read only the region of a file you
need; never print a whole file.

## No discovery
Everything you need is in this brief. Do not run orientation commands (`git log`, `git status`,
`ls`, `find`, `tree`) and do not open, `cat`, `grep` or `read` any file region that appears in
the appendices: they are the current contents. The only files you may open are listed under
"Files you may read". If you believe you need anything else, ask; do not go looking.

## Scope
Allowed to change (all inside the nested checkout `build/coucou`, branch `orca`):
- `build/coucou/NotchBuddy/Sources/App/AppState.swift` (additions only, where D1 says)
- `build/coucou/NotchBuddy/Sources/App/HookServer.swift` (the regions in Appendix B, plus new code)
- `build/coucou/NotchBuddy/Sources/App/ZaiPoller.swift` (new)
- `build/coucou/NotchBuddy/Sources/App/UsageViews.swift` (new)
- `build/coucou/NotchBuddy/Sources/App/ClaudeService.swift` (one line, D4)
- `build/coucou/NotchBuddy/Sources/App/IslandViewContent.swift` (the regions in Appendix D only)
- `build/coucou/NotchBuddy/Sources/App/SettingsView.swift` (the regions in Appendix E only)
- `build/coucou/NotchBuddy/Sources/App/AppDelegate.swift` (one line, D8)
- `docs/briefs/03-usage-card-report.md` (new; your report, in the outer repo)
Not allowed: anything else. `xcodegen` regenerating `NotchBuddy.xcodeproj` is expected.

## Files you may read (not embedded)
- `build/coucou/NotchBuddy/Sources/App/StripePoller.swift` — the poller pattern, if Appendix C
  is not enough.
- `build/coucou/NotchBuddy/Sources/App/IslandViewContent.swift` lines 2659–2720
  (`CardBackground`) — only if a compile error points there.
Nothing else.

## Build and test commands (only these)
```
cd build/coucou/NotchBuddy && xcodegen 2>&1 | tail -n 3
cd build/coucou/NotchBuddy && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' | head -n 40
```
Run `xcodegen` once after creating the two new files. No unit tests exist; a clean
`** BUILD SUCCEEDED **` with zero `error:` lines is the acceptance criterion.

## Environment
- macOS, Apple silicon, Xcode 27.0, `xcodegen` on PATH. Swift 6, `-strict-concurrency=complete`.
  `AppState`, `HookServer`'s event methods, `ClaudeService` and all views are `@MainActor`;
  pollers follow the `@unchecked Sendable` + `DispatchQueue.main.async` pattern in Appendix C.
- Outer repo `~/Workspaces/Code/coucou-orca`; nested checkout `build/coucou` on
  branch `orca` with the fork's patch already applied (Orca panes, Claude Code chat provider,
  pi pills). The app is installed and running on this Mac; you do not touch it.
- Verified facts you build on (do not re-verify):
  - Z.ai quota: `GET https://api.z.ai/api/monitor/usage/quota/limit` with header
    `Authorization: Bearer <coding-plan key>` returns Appendix G. `unit == 3` is the 5-hour
    window, `unit == 6` the weekly window; `percentage` is 0–100; `nextResetTime` is epoch
    **milliseconds**; `data.level` is the plan name ("max"). Non-200 means a bad key or outage.
  - Claude Code status-line JSON fields (Appendix H). `rate_limits` is absent until the first
    reply of a session and absent on API-key logins; `resets_at` is epoch **seconds**.
  - The user's `~/.claude/settings.json` has a `statusLine` object `{"type":"command","command":"<long shell string>"}`
    owned by Orca. The relay must preserve that command and keep running it.
  - Coucou's support dir is `HookServer.supportDir` (`~/Library/Application Support/NotchBuddy`),
    socket `HookServer.socketPath`, both created at launch by `start()`.

## Design (binding)

### D1. AppState
Add after the `activeIntegrations` property block (Appendix A shows the neighbourhood):
```swift
    // MARK: - Usage (Claude Code rate limits via status-line relay; Z.ai GLM quota via poller)

    struct ClaudeUsage: Codable, Equatable {
        var fiveHourPct: Int? = nil
        var fiveHourResetsAt: Date? = nil
        var sevenDayPct: Int? = nil
        var sevenDayResetsAt: Date? = nil
        var contextPct: Int? = nil        // for the most recently reporting session
        var contextSessionId: String? = nil
        var costUSD: Double? = nil
        var model: String? = nil
        var updatedAt: Date? = nil
        var isStale: Bool { updatedAt.map { Date().timeIntervalSince($0) > 600 } ?? true }
    }

    struct ZaiUsage: Equatable {
        var fiveHourPct: Int? = nil
        var fiveHourResetsAt: Date? = nil
        var weeklyPct: Int? = nil
        var weeklyResetsAt: Date? = nil
        var level: String? = nil
        var updatedAt: Date? = nil
        var error: String? = nil
        var isStale: Bool { updatedAt.map { Date().timeIntervalSince($0) > 600 } ?? true }
    }

    @Published var claudeUsage: ClaudeUsage = ClaudeUsage() {
        didSet {
            if let data = try? JSONEncoder().encode(claudeUsage) {
                UserDefaults.standard.set(data, forKey: "claudeUsage")
            }
        }
    }
    @Published var zaiUsage: ZaiUsage = ZaiUsage()

    /// True when the right panel should carry the usage card or strip.
    var usageConfigured: Bool {
        HookServer.statusLineRelayInstalled()
            || !(KeychainStore.shared.get("zai-api-key") ?? "").isEmpty
            || claudeUsage.updatedAt != nil
            || zaiUsage.updatedAt != nil
    }
```
In `private init()`, after the `claudeCodeModel` restore line, add:
```swift
        if let d = ud.data(forKey: "claudeUsage"),
           let u = try? JSONDecoder().decode(ClaudeUsage.self, from: d) { claudeUsage = u }
```
Note `usageConfigured` is a computed property, so views must also observe a published value to
refresh; they do, because they read `claudeUsage` / `zaiUsage` / `tasks`.

### D2. HookServer
**Event.** In the socket handler (Appendix B1) route `StatusLine` like any other event: no
change to the dispatch code is needed if you add a `case "StatusLine":` to `processEvent`'s
switch **before** the terminal-filter guard would drop it. The guard
`guard isExternalAgent || isVSCode else { … return }` runs before the switch, and a status-line
payload has no `term_program` the allowlist accepts, so insert, right before that guard:
```swift
        if name == "StatusLine" { processStatusLine(payload); return }
```
and add:
```swift
    // MARK: - Status line (Claude Code usage)

    @MainActor
    private func processStatusLine(_ payload: [String: Any]) {
        let state = AppState.shared
        var u = state.claudeUsage
        func int(_ k: String) -> Int? { (payload[k] as? NSNumber)?.intValue }
        func date(_ k: String) -> Date? { (payload[k] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        if let v = int("five_hour_pct")     { u.fiveHourPct = v }
        if let d = date("five_hour_resets_at") { u.fiveHourResetsAt = d }
        if let v = int("seven_day_pct")     { u.sevenDayPct = v }
        if let d = date("seven_day_resets_at") { u.sevenDayResetsAt = d }
        if let v = int("context_pct")       { u.contextPct = v; u.contextSessionId = payload["session_id"] as? String }
        if let c = payload["cost_usd"] as? NSNumber { u.costUSD = c.doubleValue }
        if let m = payload["model"] as? String, !m.isEmpty { u.model = m }
        u.updatedAt = Date()
        let crossed = Self.crossedAlert(old: state.claudeUsage, new: u)
        state.claudeUsage = u
        nbLog("StatusLine ctx=\(u.contextPct.map(String.init) ?? "-") 5h=\(u.fiveHourPct.map(String.init) ?? "-") 7d=\(u.sevenDayPct.map(String.init) ?? "-")")
        if crossed { SoundEngine.shared.play("rate") }
    }

    /// True when either Claude window moved from below 90 % to 90 % or more.
    private static func crossedAlert(old: AppState.ClaudeUsage, new: AppState.ClaudeUsage) -> Bool {
        func up(_ a: Int?, _ b: Int?) -> Bool { (a ?? 0) < 90 && (b ?? 0) >= 90 }
        return up(old.fiveHourPct, new.fiveHourPct) || up(old.sevenDayPct, new.sevenDayPct)
    }
```
**Relay files.** In `installHookScript()` (Appendix B2), after the `nb-hook.py` write, also
write `nb-statusline` (mode 0755) and `nb-statusline.py` (mode 0755) from the two string
constants in Appendix F, into the same directory. Add the constants at file end next to the
existing `nbHookShellWrapper`, named `nbStatusLineShell` and `nbStatusLinePython`.
**Installer.** Add, in the `#if !APPSTORE` installer area near `uninstallClaudeHooks` (Appendix B3):
```swift
    // MARK: - Status-line relay installer (Claude Code settings.statusLine)

    static var statusLineRelayPath: String { supportDir.appendingPathComponent("nb-statusline").path }
    static var statusLineUpstreamPath: String { supportDir.appendingPathComponent("statusline-upstream.sh").path }

    private static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// True when settings.statusLine.command points at Coucou's relay.
    static func statusLineRelayInstalled() -> Bool {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              let s = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sl = s["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String else { return false }
        return cmd.contains("nb-statusline")
    }

    /// The command currently configured, if any (shown in Settings before installing).
    static func currentStatusLineCommand() -> String? {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              let s = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sl = s["statusLine"] as? [String: Any] else { return nil }
        return sl["command"] as? String
    }

    /// Installs the relay: saves the previous command (if not already ours) to statusline-upstream.sh,
    /// backs up settings.json, and points settings.statusLine.command at nb-statusline.
    func installStatusLineRelay() throws {
        let url = Self.claudeSettingsURL
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { settings = parsed }
        var sl = settings["statusLine"] as? [String: Any] ?? [:]
        if let prev = sl["command"] as? String, !prev.isEmpty, !prev.contains("nb-statusline") {
            let body = "#!/bin/sh\n" + prev + "\n"
            try body.write(toFile: Self.statusLineUpstreamPath, atomically: true, encoding: .utf8)
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o700 as NSNumber], ofItemAtPath: Self.statusLineUpstreamPath)
        }
        sl["type"] = "command"
        sl["command"] = "/bin/sh \"\(Self.statusLineRelayPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        settings["statusLine"] = sl
        try Self.writeClaudeSettings(settings, backupFirst: true)
    }

    /// Removes the relay: restores the saved upstream command, or deletes statusLine if there was none.
    func uninstallStatusLineRelay() throws {
        let url = Self.claudeSettingsURL
        guard let data = try? Data(contentsOf: url),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard var sl = settings["statusLine"] as? [String: Any],
              (sl["command"] as? String)?.contains("nb-statusline") == true else { return }
        if let saved = try? String(contentsOfFile: Self.statusLineUpstreamPath, encoding: .utf8) {
            let lines = saved.split(separator: "\n", omittingEmptySubsequences: false)
            let cmd = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !cmd.isEmpty { sl["command"] = cmd; settings["statusLine"] = sl }
            else { settings.removeValue(forKey: "statusLine") }
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try Self.writeClaudeSettings(settings, backupFirst: true)
    }

    private static func writeClaudeSettings(_ settings: [String: Any], backupFirst: Bool) throws {
        let url = claudeSettingsURL
        if backupFirst, FileManager.default.fileExists(atPath: url.path) {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"
            let backup = url.deletingLastPathComponent().appendingPathComponent("settings.json.bak-\(f.string(from: Date()))")
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
```
`writeClaudeHooks()` already does its own backup; leave it as is.

### D3. ZaiPoller.swift (new)
Model it on Appendix C. Singleton `ZaiPoller.shared`, `start()` schedules a
`DispatchSourceTimer` on a background queue, first fire after 4 s, then every 60 s; `pollNow()`.
`poll()`:
- `guard let key = KeychainStore.shared.get("zai-api-key"), !key.isEmpty else { return }`.
- `GET https://api.z.ai/api/monitor/usage/quota/limit`, headers `Authorization: Bearer <key>`,
  `Accept: application/json`, `Accept-Language: en-US,en`, timeout 15 s.
- Non-200 or transport error → on main: `AppState.shared.zaiUsage.error = "Z.ai \(code)" ` (or
  the error's `localizedDescription` when code is 0), leave the other fields.
- 200 → parse Appendix G: for each entry in `data.limits`, `unit == 3` → five-hour, `unit == 6`
  → weekly; take `percentage` (Int) and `nextResetTime` (ms → `Date(timeIntervalSince1970: ms/1000)`).
  `data.level` → `level`. On main: assign all fields, `error = nil`, `updatedAt = Date()`, and
  `nbLog`-style log line via `appendAppLog("nb.log", "Zai 5h=\(…) wk=\(…) level=\(…)")`.
  Alert: if either window crossed from below 90 to 90 or more compared with the previous value,
  `SoundEngine.shared.play("rate")`.

### D4. ClaudeService.swift
In `KeychainStore.allKeys` (Appendix A2) add `"zai-api-key",` after `"openai-api-key",`.

### D5. UsageViews.swift (new)
Two SwiftUI views, dark palette matching the rest of the island (hex literals as elsewhere;
`Color(hex:)` exists).
```swift
import SwiftUI

/// Full card: two groups, two bars each. Used when no agent pills share the panel.
struct UsageCardView: View { @ObservedObject var state: AppState; var body: some View { … } }

/// One-line strip: "C ▮▮▮ 61 · 23   G ▮ 3 · 18". Used under the pills when workers run.
struct UsageStripView: View { @ObservedObject var state: AppState; var body: some View { … } }
```
Shared helpers (private, file scope):
- `barColor(pct: Int?, base: Color) -> Color`: nil → `#3B4559`; `>= 90` → `#F26B5B`; `>= 75` →
  `#F5A524`; else `base`. Claude base `#5B8DEF`, GLM base `#E0A030`.
- `pctText(_ p: Int?) -> String` → `"—"` or `"\(p)%"`.
- `resetText(_ d: Date?) -> String`: nil → `""`; same calendar day → `"HH:mm"`; otherwise
  `"EEE"` (e.g. "Mon"); use `DateFormatter` with `Locale.current`.
- `UsageRow(label: String, pct: Int?, base: Color, dim: Bool)`: `HStack` of a 48-pt label
  (`#9AA3B2`, size 10.5), a 6-pt-high rounded bar (track `#1E2330`, fill width = pct/100 of the
  available width via `GeometryReader`), and a 36-pt right-aligned monospaced value (`#C9D0DB`).
  `dim` renders the whole row at opacity 0.45.
Card layout (`VStack(alignment: .leading, spacing: 6)`, padding 12, no background of its own:
the caller wraps it in `CardBackground`):
1. Title row, uppercase monospaced 9.5 pt `#7F8A9B`: left `"claude"` (+ `" · as of HH:mm"` when
   `claudeUsage.isStale` and `updatedAt != nil`), right the two reset texts joined with `" · "`.
   If `claudeUsage.updatedAt == nil`: a single row `"claude · not reporting yet"` and, if
   `!HookServer.statusLineRelayInstalled()`, `"install the relay in Settings"` instead; skip the bars.
2. `UsageRow("5 hour", fiveHourPct, claudeBase, dim: isStale)` and `UsageRow("7 day", …)`.
3. Title row `"glm · z.ai \(level ?? "")"` with its resets; if `zaiUsage.error != nil` show
   `"glm · \(error)"` in `#F26B5B`; if no key configured (`KeychainStore.shared.get("zai-api-key")`
   empty) show `"glm · add the Z.ai key in Settings"`; skip bars in both cases.
4. `UsageRow("5 hour", …)` and `UsageRow("weekly", …)` with GLM base, dim when stale.
Strip layout (`HStack(spacing: 6)`, height 16, monospaced 9.5 pt): `"C"` in claude base, a
4-pt mini bar 44 pt wide filled to `max(fiveHourPct, sevenDayPct)` with `barColor` of that max,
then `"\(5h) · \(7d)"` as bare numbers (`"—"` when nil); a 6-pt gap; the same for `"G"` with
`max(fiveHourPct, weeklyPct)`. Values coloured `#F26B5B` when their own max ≥ 90. Add
`.help(...)` with a full-text summary (both providers, both windows, resets) so hovering the
strip shows everything.

### D6. IslandViewContent.swift
**Right panel (Appendix D1).** Replace the fixed right card with:
```swift
            // Right card: agent pills and/or usage
            let others = state.tasks.filter { $0.id != state.focusId }
            let showUsage = state.usageConfigured
            if !others.isEmpty || showUsage {
                CardBackground(wash: nil) {
                    VStack(spacing: 0) {
                        if !others.isEmpty { AgentPillsView(state: state) }
                        if showUsage {
                            if others.isEmpty {
                                UsageCardView(state: state)
                            } else {
                                UsageStripView(state: state)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                }
            }
```
and make the left card's width conditional: replace `.frame(width: 322)` with
`.frame(width: panelHidden ? nil : 322)` where `panelHidden` is `others.isEmpty && !showUsage`.
With `nil` the `HStack` gives the card the full width. Declare `others`, `showUsage` and
`panelHidden` as computed properties of `OverviewView` (they need `state`), not inside `body`.
**Context % (Appendix D1, title row).** Before the existing `if agent.steps.count > 1 { … }`
counter, add: when `agent.id == "integration_claude"`, `let ctx = state.claudeUsage.contextPct`,
show `Text("ctx \(ctx)%")` in size 11, colour `#6B7079` (or `#F5A524` when ≥ 75, `#F26B5B` when
≥ 90), followed by the existing counter.
**Side pill label (Appendix D2).** Replace the hard-coded `"VS Code"` with the catalog name:
`PillCatalog.definition(for: task.id)?.name ?? task.name`.

### D7. SettingsView.swift (Appendix E)
New state: `@State private var relayInstalled: Bool = HookServer.statusLineRelayInstalled()`,
`@State private var zaiKey: String = KeychainStore.shared.get("zai-api-key") ?? ""`.
Insert a new `GroupBox("Usage card")` **right after** the `GroupBox("Claude Code Hooks")` block:
```swift
                GroupBox("Usage card") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Shows Claude Code's 5-hour and 7-day limits and the Z.ai GLM quota in the island's right panel.")
                            .font(.system(size: 12)).foregroundColor(.secondary)

                        // Claude: status-line relay
                        HStack(spacing: 6) {
                            Circle().fill(relayInstalled ? Color(hex: "#22C55E") : Color(hex: "#F4505E")).frame(width: 8, height: 8)
                            Text(relayInstalled
                                 ? "Status-line relay installed — Claude Code reports limits to the notch"
                                 : "Status-line relay not installed — Claude limits unavailable")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        HStack(spacing: 10) {
                            Button(relayInstalled ? "Reinstall relay" : "Install relay") { confirmRelayInstall() }
                                .buttonStyle(.borderedProminent)
                            Button("Remove relay") { confirmRelayRemove() }
                                .buttonStyle(.bordered).disabled(!relayInstalled)
                        }
                        Text("Wraps the current status line (Orca's) and keeps running it. Backs up settings.json first.")
                            .font(.system(size: 10.5)).foregroundColor(.secondary)

                        Divider()

                        // GLM: Z.ai key
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: "#E0A030")).frame(width: 8, height: 8)
                            Text("Z.ai GLM coding plan").font(.system(size: 12, weight: .semibold))
                        }
                        SecureField("Z.ai API key", text: $zaiKey).textFieldStyle(.roundedBorder)
                        HStack(spacing: 10) {
                            Button("Save") {
                                KeychainStore.shared.set("zai-api-key", value: zaiKey)
                                ZaiPoller.shared.pollNow()
                                statusMessage = "✓ Z.ai key saved."
                            }.buttonStyle(.borderedProminent)
                            Button("Import from pi") { importZaiKeyFromPi() }
                        }
                        if let e = state.zaiUsage.error {
                            Text(e).font(.system(size: 11)).foregroundColor(.red)
                        } else if let t = state.zaiUsage.updatedAt {
                            Text("Last poll \(t.formatted(date: .omitted, time: .shortened)) · plan \(state.zaiUsage.level ?? "?") · 5h \(state.zaiUsage.fiveHourPct ?? 0)% · week \(state.zaiUsage.weeklyPct ?? 0)%")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    .padding(6)
                }
```
Helpers in the view:
```swift
    private func confirmRelayInstall() {
        let alert = NSAlert()
        alert.messageText = "Install the status-line relay?"
        let current = HookServer.currentStatusLineCommand()
        alert.informativeText = "settings.statusLine.command becomes:\n/bin/sh \"\(HookServer.statusLineRelayPath)\"\n\n"
            + (current.map { $0.contains("nb-statusline") ? "The relay is already installed; it will be refreshed." : "The current command is saved to statusline-upstream.sh and still runs after the relay." }
               ?? "No status line is configured today; only the relay will run.")
            + "\n\nA backup of ~/.claude/settings.json is written first."
        alert.addButton(withTitle: "Install"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try HookServer.shared.installStatusLineRelay(); relayInstalled = true; statusMessage = "✓ Relay installed. Values appear after the next Claude Code reply." }
        catch { statusMessage = "❌ \(error.localizedDescription)" }
    }
    private func confirmRelayRemove() {
        let alert = NSAlert()
        alert.messageText = "Remove the status-line relay?"
        alert.informativeText = "The previous status-line command is restored from statusline-upstream.sh."
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try HookServer.shared.uninstallStatusLineRelay(); relayInstalled = false; statusMessage = "✓ Relay removed." }
        catch { statusMessage = "❌ \(error.localizedDescription)" }
    }
    private func importZaiKeyFromPi() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent/models.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = json["providers"] as? [String: Any],
              let zai = providers["zai"] as? [String: Any],
              let key = zai["apiKey"] as? String, !key.isEmpty, !key.hasPrefix("env:") else {
            statusMessage = "❌ No Z.ai key found in ~/.pi/agent/models.json (providers.zai.apiKey)."
            return
        }
        zaiKey = key
        KeychainStore.shared.set("zai-api-key", value: key)
        ZaiPoller.shared.pollNow()
        statusMessage = "✓ Z.ai key imported from pi."
    }
```
`state` is the existing `@ObservedObject private var state = AppState.shared`.

### D8. AppDelegate.swift
In `setupIsland()`, after `NotionPoller.shared.start()`, add `ZaiPoller.shared.start()`.

### D9. What must still compile unchanged
Nothing else changes. If the compiler objects to `Date` or `Codable` in `AppState` (it already
imports Foundation and SwiftUI), say so in the report rather than restructuring.

## Tests
No test target. Acceptance is a green build. The coordinator verifies behaviour after installing
the app: piping a sample status-line JSON into `nb-statusline` must produce a `StatusLine …`
line in `~/Library/Logs/NotchBuddy/nb.log`, and importing the Z.ai key must produce a `Zai …`
line. Those log lines are therefore required, exactly as specified in D2 and D3.

## Docs (in scope)
Only your report.

## Self-verify before reporting done
1. Run the two build commands. Quote the final `BUILD SUCCEEDED` line.
2. `git -C build/coucou status --short` and `git -C build/coucou diff --stat`: only the eight
   Swift files (two new) and the regenerated `.xcodeproj`. Outer repo: only your report.
3. Write `docs/briefs/03-usage-card-report.md`: build outcome, files touched with line counts,
   out-of-scope changes at the top if any (section titled **⚠️ Out-of-scope changes — review
   required**), numbered deviations with reasons, per-error attempt accounting. Summarise in the
   `worker_done` body and set `--report-path docs/briefs/03-usage-card-report.md`.

## If anything is unclear
Ask with `orca orchestration ask --question "<question>" --timeout-ms 1800000`. If it times out,
run `orca orchestration ask --resume <message_id>`. Never guess on: the relay script contents,
the settings.json write path and backup, the Z.ai field mapping, thresholds, anything that would
make you run the app, `claude`, `pi` or `curl`. Guess freely on: private helper names, exact
paddings, label wording.

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

## Appendix A: AppState.swift neighbourhoods
A1, lines 211–222 (the block after which D1's code goes; keep intact):
```swift
    // Active integration pills (VS Code excluded — always on). Max 4.
    // Fork default: no service pills until the user checks them in Settings → Active pills.
    @Published var activeIntegrations: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(activeIntegrations)) {
                UserDefaults.standard.set(data, forKey: "activeIntegrations")
            }
        }
    }
```
A1b, the init line you add after (line 270):
```swift
        if let v = ud.string(forKey: "claudeCodeModel"), !v.isEmpty { claudeCodeModel = v }
```
A2, ClaudeService.swift lines 63–75 (`KeychainStore.allKeys`):
```swift
    private static let allKeys = [
        "anthropic-api-key",
        "google-api-key",
        "openai-api-key",
        "resend-api-key", "resend-from",
        "n8n-url", "n8n-api-key",
        "vercel-token",
        "github-token",
        "stripe-api-key",
        "calcom-api-key",
        "notion-api-key",
    ]
```

## Appendix B: HookServer.swift regions
B1, lines 135–150 (socket handler; unchanged, for orientation):
```swift
        guard !raw.isEmpty,
              let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
            return
        }

        let eventName = payload["hook_event_name"] as? String ?? ""

        if eventName == "PermissionRequest" {
            // Hold fd open — Claude Code waits for our decision (up to 120s)
            Task { @MainActor in self.processPermissionRequest(fd: fd, payload: payload) }
        } else {
            Task { @MainActor in self.processEvent(name: eventName, payload: payload) }
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
        }
```
B1b, lines 161–186 (start of `processEvent`; insert the `StatusLine` early-return right before the `guard`):
```swift
    @MainActor
    private func processEvent(name: String, payload: [String: Any]) {
        let state = AppState.shared
        let sessionId = payload["session_id"] as? String ?? "unknown"
        let cwd = payload["cwd"] as? String ?? ""
        let rawName = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        // Determine which pill this event belongs to.
        // coucou_agent must be lowercase, digits and hyphens, ≤ 24 chars.
        // Absent or invalid → Claude Code pill (integration_claude); no change in behaviour.
        let rawAgent = payload["coucou_agent"] as? String ?? ""
        let validAgent = Self.validateAgent(rawAgent)
        let agentId = validAgent.map { "agent_\($0)" } ?? "integration_claude"
        let isExternalAgent = validAgent != nil

        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""
        let isVSCode = Self.isSupportedTerminal(termProgram: termProgram, bundleId: bundleId)
        // External agents bypass the terminal filter (their relay runs in any terminal).
        guard isExternalAgent || isVSCode else {
            nbLog("Ignored \(name) from \(termProgram.isEmpty ? bundleId : termProgram) (\(projectName))")
            return
        }
```
B2, lines 557–575 (`installHookScript`, where the relay files are written):
```swift
    func installHookScript() {
        #if APPSTORE
        // In App Store mode the script is written during settings hook installation
        // (requires NSOpenPanel to ~/.claude chosen by the user)
        #else
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700 as NSNumber], ofItemAtPath: dir.path)
        // nb-hook: shell wrapper (always exits 0, calls nb-hook.py via python3)
        let wrapperURL = URL(fileURLWithPath: Self.hookScriptPath)
        try? nbHookShellWrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: wrapperURL.path)
        // nb-hook.py: Python relay
        let pyURL = wrapperURL.deletingLastPathComponent().appendingPathComponent("nb-hook.py")
        try? nbHookPythonGitHub.write(to: pyURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: pyURL.path)
        #endif
    }
```
B3, lines 684–706 (`uninstallClaudeHooks`, the pattern for settings writes; add D2's installer after it):
```swift
    func uninstallClaudeHooks() throws {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else { return }

        for key in hooks.keys {
            if var matchers = hooks[key] as? [[String: Any]] {
                matchers.removeAll { matcher in
                    (matcher["hooks"] as? [[String: Any]])?.contains {
                        ($0["command"] as? String)?.contains("NotchBuddy") == true ||
                        ($0["command"] as? String)?.contains("coucou") == true
                    } ?? false
                }
                if matchers.isEmpty { hooks.removeValue(forKey: key) }
                else { hooks[key] = matchers }
            }
        }
        settings["hooks"] = hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: settingsURL, options: .atomic)
    }
```
Other facts about this file: `static var supportDir: URL`, `static var socketPath: String`,
`static var hookScriptPath: String` exist at the top; `private func nbLog(_:)` and the free
function `appendAppLog(_ fileName: String, _ message: String)` exist; the file ends with the
string constants `nbHookShellWrapper` (line 1083), `nbHookPythonGitHub` (1099) and
`nbHookPythonAppStore` (1263). `SoundEngine.shared.play("rate")` is a valid call.

## Appendix C: StripePoller.swift, lines 1–63 (the poller pattern to copy)
```swift
import Foundation
import SwiftUI

final class StripePoller: @unchecked Sendable {
    static let shared = StripePoller()
    private var timer: DispatchSourceTimer?
    private var lastChargeId: String = ""

    private init() {}

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + 6, repeating: 30)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func pollNow() { poll() }

    private func poll() {
        guard let key = KeychainStore.shared.get("stripe-api-key") else { return }
        fetchBalance(key: key)
    }

    private func fetchBalance(key: String) {
        guard let url = URL(string: "https://api.stripe.com/v1/balance") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Basic …", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                let errMsg: String
                if code == 401 { errMsg = "Invalid API key (401)" }
                else if code == 0   { errMsg = error?.localizedDescription ?? "No connection" }
                else                { errMsg = "API error \(code)" }
                DispatchQueue.main.async { AppState.shared.stripeError = errMsg }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            // … parse …
            DispatchQueue.main.async {
                let state = AppState.shared
                state.stripeError = nil
                // … assign …
            }
        }.resume()
    }
}
```

## Appendix D: IslandViewContent.swift regions
D1, lines 34–121 (`OverviewView`; the left card's title row and the right card you change):
```swift
struct OverviewView: View {
    @ObservedObject var state: AppState
    @State private var showingN8nDetail = false

    var agent: AgentTask? { state.focusTask }

    var body: some View {
        HStack(spacing: 10) {
            // Left card: title row + ticker below + ↗ button overlay
            ZStack(alignment: .topLeading) {
                CardBackground(wash: nil)

                // Title row + ticker stacked (or integration card)
                if let agent = agent {
                    if agent.isIntegration {
                        IntegrationCardView(task: agent, showingDetail: $showingN8nDetail)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: agent.color))
                                    .frame(width: 7, height: 7)
                                Text(agent.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(hex: "#F5F6F8"))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(1)
                                Text({ () -> String in
                                    switch agent.source {
                                    case .claudeCode: return "Claude Code"
                                    case .agent:      return "Agent"
                                    case .n8n:        return "n8n"
                                    }
                                }())
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#8E939C"))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 2)
                                if agent.steps.count > 1 {
                                    Text("\(min(agent.stepIndex + 1, agent.steps.count))/\(agent.steps.count)")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "#6B7079"))
                                        .fixedSize()
                                }
                            }
                            .padding(.top, 6)
                            .padding(.leading, 108)
                            .padding(.trailing, 36)

                            TickerView(task: agent)
                                .frame(height: 44)
                                .padding(.top, 6)
                                .padding(.leading, 108)
                                .padding(.trailing, 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 4)
                    }
                }

                // ↗ jump button — last in ZStack so it renders on top; hidden while any detail is open
                if !showingN8nDetail {
                    Button(action: { openAgentTarget(agent) }) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color(hex: "#5F646D"))
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(width: 322)

            // Right card: agent pills
            CardBackground(wash: nil) {
                AgentPillsView(state: state)
            }
        }
        .onChange(of: state.focusId) { _, _ in showingN8nDetail = false }
    }
```
`CardBackground(wash: nil)` with no trailing closure is valid (there is an `EmptyView`
extension); with a closure it wraps the content. `AgentPillsView` fills whatever space it gets
(`.frame(maxWidth: .infinity, maxHeight: .infinity)`), so inside the `VStack` of D6 it keeps
the top and the strip sits below it.
D2, lines 2541–2544 (`AgentPill.displayName`):
```swift
    // VS Code pill always shows "VS Code" label regardless of active project name
    private var displayName: String {
        task.id == "integration_claude" ? "VS Code" : task.name
    }
```

## Appendix E: SettingsView.swift, the hooks box you insert after (lines 206–216 start it)
```swift
                // MARK: Hooks
                GroupBox("Claude Code Hooks") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Circle().fill(claudeHooksInstalled ? Color(hex: "#22C55E") : Color(hex: "#F4505E"))
                                .frame(width: 8, height: 8)
                            Text(claudeHooksInstalled
                                 ? "Installed in ~/.claude/settings.json — Claude Code sessions in Orca report to the notch"
                                 : "Not installed — click Install hooks and confirm the diff")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
```
That `GroupBox` ends with `.padding(6)` / `}` about 60 lines later; the next sibling is
`GroupBox("Gemini CLI")`. Insert the "Usage card" box between them. Existing helpers you reuse:
`statusMessage` (`@State String`), `state` (`AppState.shared`), `Color(hex:)`, `NSAlert`
(AppKit is imported). Existing state at the top of the view (line 27 onward) is where the two
new `@State` vars go.

## Appendix F: relay scripts, verbatim (two Swift string constants in HookServer.swift)
```swift
// nb-statusline — Claude Code status-line relay. Forwards the JSON to Coucou in the background,
// then hands it to the previous status-line command (saved at install time) so its output still shows.
private let nbStatusLineShell = """
#!/bin/sh
# Coucou status-line relay — forwards Claude Code's status JSON to Coucou, then runs the previous status line
DIR="$(cd "$(dirname "$0")" && pwd)"
payload=$(cat)
[ -z "$payload" ] && exit 0
if xcode-select -p >/dev/null 2>&1; then
    printf '%s' "$payload" | /usr/bin/python3 "$DIR/nb-statusline.py" >/dev/null 2>&1 &
fi
if [ -s "$DIR/statusline-upstream.sh" ]; then
    printf '%s' "$payload" | /bin/sh "$DIR/statusline-upstream.sh"
fi
exit 0
"""

private let nbStatusLinePython = """
#!/usr/bin/env python3
# nb-statusline.py — reads Claude Code status-line JSON on stdin, forwards a compact StatusLine event to Coucou.
import sys, json, os, socket, time

def main():
    try:
        payload = json.loads(sys.stdin.buffer.read() or b'{}')
    except Exception:
        return
    sid = str(payload.get('session_id') or '')
    # Throttle: at most one event per session every 3 s (Claude Code redraws often while streaming).
    stamp = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'coucou-statusline-' + (sid[:8] or 'x'))
    try:
        if time.time() - os.path.getmtime(stamp) < 3:
            return
    except OSError:
        pass
    try:
        open(stamp, 'w').close()
    except OSError:
        pass
    cw = payload.get('context_window') or {}
    rl = payload.get('rate_limits') or {}
    fh = rl.get('five_hour') or {}
    sd = rl.get('seven_day') or {}
    model = payload.get('model') or {}
    cost = payload.get('cost') or {}
    out = {
        'hook_event_name': 'StatusLine',
        'session_id': sid,
        'cwd': payload.get('cwd') or '',
        'model': model.get('display_name') or model.get('id') or '',
        'term_program': os.environ.get('TERM_PROGRAM', ''),
        'bundle_id': os.environ.get('__CFBundleIdentifier', ''),
    }
    if isinstance(cw.get('used_percentage'), (int, float)):
        out['context_pct'] = int(round(cw['used_percentage']))
    if isinstance(cost.get('total_cost_usd'), (int, float)):
        out['cost_usd'] = float(cost['total_cost_usd'])
    if isinstance(fh.get('used_percentage'), (int, float)):
        out['five_hour_pct'] = int(round(fh['used_percentage']))
    if isinstance(fh.get('resets_at'), (int, float)):
        out['five_hour_resets_at'] = int(fh['resets_at'])
    if isinstance(sd.get('used_percentage'), (int, float)):
        out['seven_day_pct'] = int(round(sd['used_percentage']))
    if isinstance(sd.get('resets_at'), (int, float)):
        out['seven_day_resets_at'] = int(sd['resets_at'])
    path = os.path.expanduser('~/Library/Application Support/NotchBuddy/nb.sock')
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(path)
        s.sendall((json.dumps(out) + '\\n').encode())
        s.close()
    except Exception:
        pass

if __name__ == '__main__':
    main()
    sys.exit(0)
"""
```
(Inside a Swift multi-line string, `\\n` yields the two characters backslash-n in the written
Python file, which is what the Python source needs. The existing `nbHookPythonGitHub` constant
uses the same convention.)

## Appendix G: Z.ai quota response, verbatim from this Mac today
```json
{"code":200,"msg":"Operation successful","success":true,
 "data":{"level":"max","limits":[
   {"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":28000,"currentValue":1050,"remaining":26949,"percentage":3,"nextResetTime":1790945154517},
   {"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":140000,"currentValue":26579,"remaining":113420,"percentage":18,"nextResetTime":1791186639982}]}}
```

## Appendix H: Claude Code status-line JSON, the fields used
`session_id`, `cwd`, `model.id`, `model.display_name`, `cost.total_cost_usd`,
`context_window.used_percentage`, `rate_limits.five_hour.used_percentage`,
`rate_limits.five_hour.resets_at` (epoch seconds), `rate_limits.seven_day.used_percentage`,
`rate_limits.seven_day.resets_at`. `rate_limits` is present only for claude.ai Pro and Max
logins and only after the first reply of a session.
