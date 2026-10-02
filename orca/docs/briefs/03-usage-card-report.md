# Report — brief 03-usage-card (task_ae968265eccb)

## Build outcome

Final build (after all 8 steps), exactly per the brief's command:

```
** BUILD SUCCEEDED **
```

Zero `error:` lines at every build. Three builds were run, all green:
1. after step 2 (AppState + HookServer): `** BUILD SUCCEEDED **`
2. after step 5 (+ ZaiPoller, ClaudeService, UsageViews; `xcodegen` run once here): `** BUILD SUCCEEDED **`
3. final (all 8 steps): `** BUILD SUCCEEDED **`

`xcodegen` was run exactly once ("Created project at …/NotchBuddy/NotchBuddy.xcodeproj").

## ⚠️ Out-of-scope changes — review required

**None made by this task.** For completeness, three pre-existing / artifact states were
observed and left untouched:

1. Nested checkout: `NotchBuddy/Sources/App/ClaudeCodeCLI.swift` is untracked and **pre-dates
   this task** (mtime 18:43, before this session started at ~19:20). It is not included in the
   regenerated `project.pbxproj` (the +18-line diff is exactly the two new files below) and was
   not created or modified by me.
2. Outer repo: `scripts/build.sh` and `test/run-tests.sh` were already modified before this task
   began; I did not touch them.
3. `xcodegen`/`xcodebuild` created `NotchBuddy/NotchBuddy.xcodeproj/xcshareddata/` (shared
   scheme data). This is an artifact of the allowed build commands, inside the expected
   regenerated `.xcodeproj`; flagged in case you don't want it committed.

## Files touched (nested checkout `build/coucou`, branch `orca`)

| File | Change |
|---|---|
| `NotchBuddy/Sources/App/AppState.swift` | +45 lines (D1: `ClaudeUsage`, `ZaiUsage`, published fields, `usageConfigured`, init restore) |
| `NotchBuddy/Sources/App/HookServer.swift` | +193 lines (D2: `StatusLine` routing, `processStatusLine`/`crossedAlert`, relay script writes in `installHookScript`, installer/uninstaller + `writeClaudeSettings` backup, `nbStatusLineShell`/`nbStatusLinePython` at file end) |
| `NotchBuddy/Sources/App/ZaiPoller.swift` | new, 81 lines (D3) |
| `NotchBuddy/Sources/App/UsageViews.swift` | new, 216 lines (D5: `UsageCardView`, `UsageStripView`, helpers) |
| `NotchBuddy/Sources/App/ClaudeService.swift` | +1 line (D4: `"zai-api-key",` in `allKeys`) |
| `NotchBuddy/Sources/App/IslandViewContent.swift` | +30/−6 lines (D6: right panel, conditional left width, ctx %, pill label) |
| `NotchBuddy/Sources/App/SettingsView.swift` | +90 lines (D7: "Usage card" GroupBox, 2 `@State` vars, 3 helpers) |
| `NotchBuddy/Sources/App/AppDelegate.swift` | +1 line (D8: `ZaiPoller.shared.start()`) |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | regenerated (+18) |

`git status --short` (nested): the seven modified files above, `?? UsageViews.swift`,
`?? ZaiPoller.swift`, plus the pre-existing `?? ClaudeCodeCLI.swift` and `?? xcshareddata/`
noted above. Outer repo: only this report (plus the two pre-existing modifications I did not
make). Nothing was committed, per the rules.

## Numbered deviations

1. **ctx % shown only when non-nil** (D6 title row). The brief says show
   `Text("ctx \(ctx)%")` with `let ctx = state.claudeUsage.contextPct` (an `Int?`); literal
   interpolation of nil renders "ctx nil%". I render the view only when `contextPct != nil`,
   with the specified colours (≥ 90 → `#F26B5B`, ≥ 75 → `#F5A524`, else `#6B7079`, size 11).
2. **Minimal anchor reads outside the appendices.** The brief mandates edits whose insertion
   points it describes but does not embed: the `@State` block of `SettingsView` (read lines
   20–48), the sibling GroupBox label (grepped `GroupBox(` — actual label is
   `"Gemini CLI Hooks"`, not `"Gemini CLI"`), and the `NotionPoller.shared.start()` line in
   `AppDelegate` (grepped for exact indentation). No other file regions were opened beyond the
   appendices, the two new files I wrote, and my own edits.
3. **Comment above `AgentPill.displayName` updated** to describe the new behaviour (was
   "VS Code pill always shows "VS Code" label…"); code uses the mandated
   `PillCatalog.definition(for: task.id)?.name ?? task.name` for `integration_claude`.
4. **`others` / `showUsage` / `panelHidden` as computed properties**, and `body` references
   them directly instead of re-declaring local `let`s as in the D6 snippet (the snippet and the
   "not inside body" instruction conflict; I followed the instruction).
5. **ZaiPoller error strings**: `code == 0` with no `error` → `"Z.ai no connection"` (the brief
   specifies `localizedDescription` when code is 0 but no fallback for a nil error).
6. **ZaiPoller `level`**: `data.level` empty string → stored as `nil` (card title prints
   `"glm · z.ai "` with trailing space otherwise).
7. **Strip red-value guard**: the `C`/`G` value text turns `#F26B5B` only when that provider's
   max is *known* and ≥ 90 (a nil/unknown max stays `#C9D0DB`); the mini-bar fill uses
   `barColor` of the max, with the grey track colour when nothing is known.

## Per-error attempt accounting

- **Compile errors: none.** All three builds were clean on the first attempt; no error ever
  consumed an attempt.
- One non-compile failure: my first `SettingsView` edit anchored on `GroupBox("Gemini CLI")`
  (the brief's wording) while the real label is `GroupBox("Gemini CLI Hooks")`; the edit tool
  rejected the match atomically (nothing was applied), I grepped the actual label, and the
  retry succeeded — one failed attempt, fixed on the second, no file ever in a broken state.

## Behaviour notes for verification (per the brief's Tests section)

- The relay scripts are written by `installHookScript()` into
  `HookServer.supportDir` as `nb-statusline` (0755) and `nb-statusline.py` (0755), content
  verbatim from Appendix F (`\\n` preserved so the written Python contains `'\n'`).
- A `StatusLine` socket event updates `claudeUsage`, logs
  `StatusLine ctx=… 5h=… 7d=…` via `nbLog` (→ `~/Library/Logs/NotchBuddy/nb.log`), and plays
  the "rate" sound when a Claude window crosses 90 %.
- ZaiPoller logs `Zai 5h=… wk=… level=…` to `nb.log` via `appendAppLog` on each successful
  poll and sets `error = "Zai <code>"` / transport description otherwise.
- The app, its socket, `claude`, `pi`, `curl` and any container/port were never touched, per
  the machine and environment rules.
