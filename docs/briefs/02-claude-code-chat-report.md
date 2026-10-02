# Report: Claude Code chat provider (brief 02)

## ⚠️ Out-of-scope changes — review required

None. Only the six allowed Swift files (one new) were touched, plus the expected `xcodegen`
regeneration of `NotchBuddy.xcodeproj` (brief: expected, not reported as a change — details in
Self-verification for transparency). The outer repo shows only this report file.

## Build outcome

Final build command (exactly as specified in the brief):

```
cd build/coucou/NotchBuddy && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy \
  -configuration Release -derivedDataPath build build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 \
  | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' | head -n 40
```

Output (complete):

```
** BUILD SUCCEEDED **
```

Zero `error:` lines. Acceptance criterion met. `xcodegen` was run once, immediately after
creating `ClaudeCodeCLI.swift` (output: `Created project at …/NotchBuddy.xcodeproj`).

## Files touched (inner checkout `build/coucou`, branch `orca`)

| File | Status | Lines |
|---|---|---|
| `NotchBuddy/Sources/App/ClaudeCodeCLI.swift` | new | 160 (Appendix F verbatim) |
| `NotchBuddy/Sources/App/IslandTypes.swift` | modified | +5 / −0 |
| `NotchBuddy/Sources/App/AppState.swift` | modified | +17 / −1 |
| `NotchBuddy/Sources/App/ClaudeService.swift` | modified | +93 / −0 |
| `NotchBuddy/Sources/App/IslandViewContent.swift` | modified | +1 / −0 |
| `NotchBuddy/Sources/App/SettingsView.swift` | modified | +40 / −2 |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | modified | +6 / −0 (xcodegen) |

What each change implements:

- **ClaudeCodeCLI.swift** — verbatim from Appendix F: binary discovery (`locate()`, honoring
  `COUCOU_CLAUDE_BIN`), `version()`, and headless `run()` with `--output-format json`,
  `--resume`, `--add-dir`, `--append-system-prompt`, `--allowedTools`, optional `--model`,
  120 s timeout, concurrent stderr drain, JSON result parsing.
- **IslandTypes.swift** — `case claudeCode = "claude-code"` added first in `ChatProvider`;
  `displayName` "Claude Code", `accentHex` "#E0A030", `defaultModel` "default", `keychainKey` "".
- **AppState.swift** — default `chatProvider = .claudeCode`; persisted `claudeCodeModel`
  (`didSet` + init restore); `activeChatModel` returns it; `fetchModelsIfNeeded` handles Claude
  Code synchronously as its first statement (CLI-missing error message or the static
  `ClaudeCodeCLI.modelChoices` list) and returns before the Keychain guard; `case .claudeCode`
  added to both inner switches.
- **ClaudeService.swift** — `claudeCodeSessionId` property, nilled by `clearConversation()`;
  `chat()` and `search()` route to `chatViaClaudeCode` / `searchViaClaudeCode` as their first
  statement; both new methods verbatim from D3; `chatOpenAICompatible`'s baseURL switch gained
  `case .claudeCode: return` beside `.anthropic`; `handleResult` split so the text handling
  (fence-stripping onward, unchanged code) lives in the new `handleResultText`.
- **IslandViewContent.swift** — model picker button switch gained
  `case .claudeCode: state.claudeCodeModel = model.id`.
- **SettingsView.swift** — `claudeCLIPath` / `claudeCLIVersion` state; `loadCLIVersion()`
  helper; `GroupBox("Claude Code (local)")` inserted before the Anthropic box (status dot,
  found-path + version line, model picker over `ClaudeCodeCLI.modelChoices`, "Use Claude Code
  for chat" + "Re-detect" buttons, `.task { loadCLIVersion() }`); Anthropic box retitled
  "Anthropic API (optional)" with the new trailing hint text.

## Deviations from the brief

1. **`case .claudeCode: models = []` instead of `case .claudeCode: break`** in
   `fetchModelsIfNeeded`'s first inner switch (the one assigning `let models`). Reason: with
   `break` the switch leaves `models` uninitialized on that path, which cannot compile
   ("constant 'models' used before being initialized") since `models` is read after the switch.
   The case is unreachable in practice (Claude Code returns before the Task). **Pre-approved by
   the coordinator in the plan gate** ("(a) yes: case .claudeCode: models = [] in the first
   inner switch, and case .claudeCode: break in the second").
2. **The Claude Code block sits as the very first statement of `fetchModelsIfNeeded`, before the
   loading/fetched-cached guard** (the brief said "at the top, before the Keychain guard", which
   is ambiguous between the two guards). Consequence: repeated calls re-run the cheap
   `locate()` and refresh the cached list instead of early-returning on the cache. **Pre-approved
   by the coordinator in the plan gate** ("(b) yes: first statement of fetchModelsIfNeeded,
   before the loading/fetched guard").

No other deviations. Notable non-deviating choice: for `searchViaClaudeCode` the brief allowed
either duplicating the search system-prompt literal or hoisting it into a shared
`searchSystemPrompt` property; I used the literal verbatim as printed in D3, so `search()`'s
existing code is untouched. `loadCLIVersion()` was placed immediately before `var body` (the
brief left helper placement free).

## Per-error attempt accounting

- **Build #1 (after step 3): FAILED — 2 errors, 0 fix attempts consumed.**
  `ClaudeService.swift:265: switch must be exhaustive` and
  `IslandViewContent.swift:959: switch must be exhaustive`. Both were predicted before building
  (announced in status msg_64d6dee30a68) and are the errors the brief's own step ordering
  produces: they are fixed by steps 4 and 5 respectively, not by retries.
- **Build #2 (after step 4): FAILED — 1 error, 0 fix attempts consumed.**
  Only `IslandViewContent.swift:959: switch must be exhaustive` remained (ClaudeService error
  cleared by step 4); fixed by the planned step 5 edit.
- **Build #3 (final, after step 6): SUCCEEDED on the first attempt**, zero `error:` lines.

No build error ever needed a second attempt; the two-attempt budget was never touched.

## Self-verification

- `git -C build/coucou status --short`: the six Swift files (five `M`, one `??` =
  `ClaudeCodeCLI.swift`), `M NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`, and
  `?? NotchBuddy/NotchBuddy.xcodeproj/xcshareddata/` (see note below).
- `git -C build/coucou diff --stat`: 6 files, 162 insertions, 3 deletions (table above).
- Outer repo `git status --short`: only this report (`docs/briefs/02-claude-code-chat-report.md`).
- Note for transparency: the untracked `xcshareddata/` directory (two shared scheme files,
  `NotchBuddy.xcscheme` and `CoucouAppStore.xcscheme`) was emitted by xcodegen/xcodebuild
  **inside** the `.xcodeproj` bundle, which the brief declares expected and not reportable;
  it is mentioned here only because it is untracked rather than a modification.
- The app was not launched; `claude` was not run; no container, port, commit, or forbidden path
  was touched.
