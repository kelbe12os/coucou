# Brief: chat through the local Claude Code CLI (no API key)

## Task
Coucou's chat currently needs an Anthropic API key. Add a fourth chat provider, **Claude Code**,
that runs the user's locally installed `claude` CLI in headless mode (`claude -p`) and therefore
uses the user's existing Claude Code login. Make it the default provider for this fork. Build, in
this order:
1. `ClaudeCodeCLI.swift` (new file, Appendix F, create verbatim) — locates the binary and runs it.
2. `IslandTypes.swift` — new `ChatProvider.claudeCode` case.
3. `AppState.swift` — default provider, persisted model choice, static model list, exhaustive switches.
4. `ClaudeService.swift` — route `chat()` and `search()` to the CLI when the provider is Claude Code.
5. `IslandViewContent.swift` — the model picker's one exhaustive switch.
6. `SettingsView.swift` — a "Claude Code (local)" box above the Anthropic box.
7. Regenerate the Xcode project (new file) and build.

Fully implemented, no stubs, no TODOs.
Rules: write each file as soon as it is drafted, build early (build after step 3, after step 4, and
at the end), at most two attempts per failing build error; an error you cannot fix in two attempts
is left and explained in the report. Do not commit anywhere. The coordinator reviews and commits.
Environment rule: do not create, recreate, stop, start or reconfigure any container, and do not
change any port. If the environment is not as described below, stop and ask.
Working-tree rule: never run git stash, reset, checkout, switch, clean or rebase, in either git
repository below. If you need to compare with HEAD, use git diff or git show.
Machine rule: never run `claude`, `scripts/build.sh`, `codesign`, `ditto`, `sudo`, `open`, and
never write under `~/.claude`, `~/.pi`, `~/Library` or `/Applications`. The app must not be
launched by you. `xcodegen` and `xcodebuild` are allowed exactly as written under "Build and test
commands".
Context rule: pipe build output through the grep given below; read only the region of a file you
need; never print a whole file.

## No discovery
Everything you need is in this brief. Do not run orientation commands (`git log`, `git status`,
`ls`, `find`, `tree`) and do not open, `cat`, `grep` or `read` any file region that appears in
the appendices: they are the current contents. The only files you may open are listed under
"Files you may read". If you believe you need anything else, ask; do not go looking.

## Scope
Allowed to change (all inside the nested checkout `build/coucou`, on its current branch `orca`):
- `build/coucou/NotchBuddy/Sources/App/ClaudeCodeCLI.swift` (new)
- `build/coucou/NotchBuddy/Sources/App/IslandTypes.swift` (the `ChatProvider` enum only)
- `build/coucou/NotchBuddy/Sources/App/AppState.swift` (the regions in Appendix B only)
- `build/coucou/NotchBuddy/Sources/App/ClaudeService.swift` (the regions in Appendix C only)
- `build/coucou/NotchBuddy/Sources/App/IslandViewContent.swift` (the one switch in Appendix D only)
- `build/coucou/NotchBuddy/Sources/App/SettingsView.swift` (the region in Appendix E only)
- `docs/briefs/02-claude-code-chat-report.md` (new; your report, in the outer repo)
Not allowed: anything else, in either repository. `xcodegen` rewrites
`build/coucou/NotchBuddy/NotchBuddy.xcodeproj`; that is expected and not a change you report.

## Files you may read (not embedded)
- `build/coucou/NotchBuddy/Sources/App/ClaudeService.swift` lines 1–57 (Keychain helper) — only
  if a compile error points there.
- `build/coucou/NotchBuddy/Sources/App/IslandViewContent.swift` lines 780–830 — only if a compile
  error points there.
Nothing else.

## Build and test commands (only these)
```
cd build/coucou/NotchBuddy && xcodegen 2>&1 | tail -n 3
cd build/coucou/NotchBuddy && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' | head -n 40
```
Run `xcodegen` once after creating `ClaudeCodeCLI.swift` (the project lists source files
explicitly) and again if you add any other file. An incremental build takes one to two minutes.
There are no unit tests in this project; a clean `** BUILD SUCCEEDED **` with zero `error:` lines
is the acceptance criterion. Do not build any other scheme or configuration.

## Environment
- macOS, Apple silicon, Xcode 27.0 at `/Applications/Xcode.app`, `xcodegen` on PATH.
- Outer repo: `<repo>` (branch `main`). Inside it,
  `build/coucou` is a separate git checkout of upstream Coucou (gitignored by the outer repo)
  on branch `orca`, which already carries the fork's patch. You edit files there.
- The project uses Swift 6 with `-strict-concurrency=complete`. `AppState`, `ClaudeService` and
  the views are `@MainActor`. Appendix F is written to compile under those settings; keep it
  verbatim.
- The `claude` CLI exists at `~/.local/bin/claude` (version 2.1.284). You must not
  run it. Its headless contract is in Appendix G and was verified on this machine today.

## Design (binding)

### D1. `ChatProvider` (IslandTypes.swift)
Add a case **first** in the enum so it is the leading chip in the picker:
```swift
case claudeCode = "claude-code"
```
Switch values: `displayName` → `"Claude Code"`; `accentHex` → `"#E0A030"`; `defaultModel` →
`"default"`; `keychainKey` → `""` (never used for this case; every caller is guarded below).

### D2. `AppState` (AppState.swift, Appendix B regions)
- Default provider becomes the fork default: `chatProvider: ChatProvider = .claudeCode`.
- New persisted property, right after `openAIChatModel`:
  ```swift
  @Published var claudeCodeModel: String = ChatProvider.claudeCode.defaultModel {
      didSet { UserDefaults.standard.set(claudeCodeModel, forKey: "claudeCodeModel") }
  }
  ```
  and in `init`, after the `openAIChatModel` line:
  `if let v = ud.string(forKey: "claudeCodeModel"), !v.isEmpty { claudeCodeModel = v }`.
- `activeChatModel`: add `case .claudeCode: return claudeCodeModel`.
- `fetchModelsIfNeeded(for:)`: at the top, before the Keychain guard, handle Claude Code
  synchronously and return:
  ```swift
  if provider == .claudeCode {
      if ClaudeCodeCLI.locate() == nil {
          providerModelFetchError[provider] = "Claude Code CLI not found. Install Claude Code, or set COUCOU_CLAUDE_BIN."
      } else {
          providerModelFetchError.removeValue(forKey: provider)
          fetchedProviderModels[provider] = ClaudeCodeCLI.modelChoices
      }
      return
  }
  ```
  In the two inner `switch provider` statements add `case .claudeCode: break` (they are
  unreachable for this provider but must stay exhaustive).

### D3. `ClaudeService` (ClaudeService.swift, Appendix C regions)
- New stored property next to `conversationMessages`: `private var claudeCodeSessionId: String?`.
  `clearConversation()` also sets it to `nil`.
- `chat(query:context:state:)`: insert as the very first statement
  `if state.chatProvider == .claudeCode { await chatViaClaudeCode(query: query, context: context, state: state); return }`.
- New method:
  ```swift
  private func chatViaClaudeCode(query: String, context: PromptContext?, state: AppState) async {
      var prompt = query
      var addDirs: [String] = []
      var cwd: String? = nil
      if claudeCodeSessionId == nil, let context {
          switch context {
          case .window(let app, let title, let url):
              var text = "Context — App: \(app), Window: \(title)"
              if let url { text += ", URL: \(url)" }
              prompt = text + "\n\n" + query
          case .file(let name, let fileURL):
              if let fileURL {
                  let dir = fileURL.deletingLastPathComponent().path
                  addDirs = [dir]; cwd = dir
                  prompt = "Read the file at \(fileURL.path) with the Read tool first.\nFile: \(name)\n\n" + query
              } else {
                  prompt = "File: \(name)\n\n" + query
              }
          }
      }
      do {
          let out = try await ClaudeCodeCLI.run(prompt: prompt, systemPrompt: systemPrompt,
                                                model: state.claudeCodeModel,
                                                resumeSessionId: claudeCodeSessionId,
                                                addDirs: addDirs, cwd: cwd)
          if out.isError {
              await showError("Claude Code: \(out.text.isEmpty ? "request failed" : out.text)", state: state)
              return
          }
          if let sid = out.sessionId, !sid.isEmpty { claudeCodeSessionId = sid }
          guard !out.text.isEmpty else { await showError("No response text.", state: state); return }
          state.chatHistory.append(ChatMessage(role: .assistant, content: out.text))
          state.stateOverride = nil
          state.view = .prompt
          NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
      } catch {
          await showError("Claude Code: \(error.localizedDescription)", state: state)
      }
  }
  ```
- `chatOpenAICompatible`: in the `switch provider` that picks `baseURL`, add
  `case .claudeCode: return` next to `case .anthropic: return`.
- `search(query:context:state:)`: insert as the very first statement
  `if state.chatProvider == .claudeCode { await searchViaClaudeCode(query: query, context: context, state: state); return }`.
  Then refactor `handleResult(_ data: Data, state:)` so its text handling lives in a new
  `private func handleResultText(_ text: String, state: AppState) async` (everything from
  "Strip markdown code fences" to the end), and `handleResult` extracts `text` as today and calls
  it. New method:
  ```swift
  private func searchViaClaudeCode(query: String, context: PromptContext?, state: AppState) async {
      var prompt: String
      var addDirs: [String] = []
      var cwd: String? = nil
      switch context {
      case .window(let appName, let title, let url):
          prompt = "App: \(appName)\nWindow title: \(title)"
          if let url { prompt += "\nURL: \(url)" }
          prompt += "\n\nRequest: \(query)"
      case .file(let name, let fileURL):
          if let fileURL {
              let dir = fileURL.deletingLastPathComponent().path
              addDirs = [dir]; cwd = dir
              prompt = "Read the file at \(fileURL.path) with the Read tool first.\nFile: \(name)\n\nRequest: \(query)"
          } else {
              prompt = "File: \(name)\n\nRequest: \(query)"
          }
      case nil:
          prompt = query
      }
      let system = """
      You are an assistant built into the notch of a Mac. Reply in English, short and precise.
      Reply ONLY with valid JSON in this exact format:
      {"title":"...","items":[{"label":"...","detail":"...","url":"..."}],"note":"..."}
      Maximum 3 items. "url" is optional. "note" is optional.
      """
      do {
          let out = try await ClaudeCodeCLI.run(prompt: prompt, systemPrompt: system,
                                                model: state.claudeCodeModel, resumeSessionId: nil,
                                                addDirs: addDirs, cwd: cwd)
          if out.isError { await showError("Claude Code: \(out.text)", state: state); return }
          await handleResultText(out.text, state: state)
      } catch {
          await showError("Claude Code: \(error.localizedDescription)", state: state)
      }
  }
  ```
  (`system` is the same literal `search()` already uses; reuse it by moving it to a
  `private let searchSystemPrompt` if you prefer, used by both. Either is fine.)

### D4. `ModelPickerView` (IslandViewContent.swift, Appendix D)
In the model button's `switch state.chatProvider`, add `case .claudeCode: state.claudeCodeModel = model.id`.
Nothing else in this file changes.

### D5. Settings (SettingsView.swift, Appendix E)
- New state: `@State private var claudeCLIPath: String? = ClaudeCodeCLI.locate()` and
  `@State private var claudeCLIVersion: String = ""`.
- Insert a new `GroupBox("Claude Code (local)")` **before** `GroupBox("Anthropic API")`:
  ```swift
  GroupBox("Claude Code (local)") {
      VStack(alignment: .leading, spacing: 8) {
          Text("Chat through your Claude Code login (claude -p). No API key needed.")
              .font(.system(size: 12)).foregroundColor(.secondary)
          HStack(spacing: 6) {
              Circle().fill(claudeCLIPath == nil ? Color(hex: "#F4505E") : Color(hex: "#22C55E"))
                  .frame(width: 8, height: 8)
              if let p = claudeCLIPath {
                  Text("Found: \(p)\(claudeCLIVersion.isEmpty ? "" : " · \(claudeCLIVersion)")")
                      .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
              } else {
                  Text("claude CLI not found. Install Claude Code, or set COUCOU_CLAUDE_BIN.")
                      .font(.system(size: 11))
              }
          }
          Picker("Model", selection: $state.claudeCodeModel) {
              ForEach(ClaudeCodeCLI.modelChoices, id: \.id) { m in Text(m.label).tag(m.id) }
          }
          HStack(spacing: 8) {
              Button(state.chatProvider == .claudeCode ? "✓ Used for chat" : "Use Claude Code for chat") {
                  state.chatProvider = .claudeCode
                  statusMessage = "✓ Chat now uses Claude Code."
              }
              .buttonStyle(.borderedProminent)
              .disabled(state.chatProvider == .claudeCode || claudeCLIPath == nil)
              Button("Re-detect") { claudeCLIPath = ClaudeCodeCLI.locate(); loadCLIVersion() }
          }
      }
      .padding(6)
  }
  .task { loadCLIVersion() }
  ```
  and a helper in the view:
  ```swift
  private func loadCLIVersion() {
      Task { claudeCLIVersion = await ClaudeCodeCLI.version() ?? "" }
  }
  ```
- Retitle the existing box to `GroupBox("Anthropic API (optional)")` and change its trailing hint
  text to `"Only needed if you prefer the API over your Claude Code login. The list comes from your Anthropic account."`.
  Nothing else in Settings changes.

### D6. What must still compile unchanged
`switchChatProvider`, the AI pills (`ai_anthropic`, `ai_google`, `ai_openai`) and the idle-card
status labels are untouched. If the compiler reports a non-exhaustive switch anywhere else over
`ChatProvider`, add a `case .claudeCode:` branch that mirrors `.anthropic` and list it under
deviations.

## Tests
No test target. Acceptance is the build command above ending in `** BUILD SUCCEEDED **` with zero
`error:` lines, after `xcodegen`. Do not run the app and do not run `claude`.

## Docs (in scope)
Only your report.

## Self-verify before reporting done
1. Run the two build commands. Quote the final `BUILD SUCCEEDED` line. At most two attempts per
   compile error; leave anything else failing and say why.
2. `git -C build/coucou status --short` and `git -C build/coucou diff --stat`: only the six Swift
   files (one new) and the regenerated `.xcodeproj` may appear. In the outer repo
   `git status --short` must show only your report.
3. Write the full report to `docs/briefs/02-claude-code-chat-report.md`: build outcome, files
   touched with line counts, out-of-scope changes at the top if any (section titled
   **⚠️ Out-of-scope changes — review required**), numbered deviations from this brief with
   reasons, per-error attempt accounting. Summarise it in the `worker_done` body and set
   `--report-path docs/briefs/02-claude-code-chat-report.md`.

## If anything is unclear
Ask with `orca orchestration ask --question "<question>" --timeout-ms 1800000`. If it times out,
run `orca orchestration ask --resume <message_id>`. Never guess on: the CLI arguments, the
environment variables set for the child process, the exhaustiveness fixes, anything that would
make you run `claude` or the app. Guess freely on: private helper names, spacing, label wording.

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

## Appendix A: IslandTypes.swift, lines 66–104 (the enum you change)
```swift
// MARK: - Chat provider

enum ChatProvider: String, CaseIterable, Codable {
    case anthropic = "anthropic"
    case google    = "google"
    case openai    = "openai"

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .google:    "Google"
        case .openai:    "OpenAI"
        }
    }

    var accentHex: String {
        switch self {
        case .anthropic: "#E07950"
        case .google:    "#4285F4"
        case .openai:    "#10A37F"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-4-6"
        case .google:    "gemini-2.0-flash"
        case .openai:    "gpt-4o"
        }
    }

    var keychainKey: String {
        switch self {
        case .anthropic: "anthropic-api-key"
        case .google:    "google-api-key"
        case .openai:    "openai-api-key"
        }
    }
}
```
Rest of the file: layout structs and enums; keep intact.

## Appendix B: AppState.swift, lines 56–132 and 251–254 (the regions you change)
```swift
    // Claude model used by the chat and the search — persisted
    static let defaultClaudeModel = "claude-sonnet-4-6"
    @Published var claudeModel: String = AppState.defaultClaudeModel {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }

    // In-chat provider + model — picked via the model selector in the prompt view
    @Published var chatProvider: ChatProvider = .anthropic {
        didSet { UserDefaults.standard.set(chatProvider.rawValue, forKey: "chatProvider") }
    }
    @Published var googleChatModel: String = ChatProvider.google.defaultModel {
        didSet { UserDefaults.standard.set(googleChatModel, forKey: "googleChatModel") }
    }
    @Published var openAIChatModel: String = ChatProvider.openai.defaultModel {
        didSet { UserDefaults.standard.set(openAIChatModel, forKey: "openAIChatModel") }
    }

    // The always-on workspace pill (default: VS Code). Persisted.
    @Published var mainPillId: String = PillCatalog.defaultMainPillId {
        didSet { UserDefaults.standard.set(mainPillId, forKey: "mainPill") }
    }

    // Dynamically fetched model lists for the in-chat picker (keyed by provider)
    @Published var fetchedProviderModels: [ChatProvider: [(id: String, label: String)]] = [:]
    @Published var providerModelFetchError: [ChatProvider: String] = [:]
    @Published var loadingProviderModels: Set<ChatProvider> = []

    /// Fetches models for `provider` if not already loaded or loading.
    /// Sets `providerModelFetchError` if the key is absent or the request fails.
    func fetchModelsIfNeeded(for provider: ChatProvider) {
        guard !loadingProviderModels.contains(provider),
              fetchedProviderModels[provider] == nil else { return }
        guard let apiKey = KeychainStore.shared.get(provider.keychainKey), !apiKey.isEmpty else {
            providerModelFetchError[provider] = "No API key — add it in Settings."
            return
        }
        loadingProviderModels.insert(provider)
        providerModelFetchError.removeValue(forKey: provider)
        Task {
            let models: [(id: String, label: String)]
            switch provider {
            case .anthropic: models = await ClaudeService.fetchModels(apiKey: apiKey)
            case .google:    models = await ClaudeService.fetchGoogleModels(apiKey: apiKey)
            case .openai:    models = await ClaudeService.fetchOpenAIModels(apiKey: apiKey)
            }
            loadingProviderModels.remove(provider)
            if models.isEmpty {
                providerModelFetchError[provider] = "Failed to load models. Check your API key."
            } else {
                fetchedProviderModels[provider] = models
                // If the saved model isn't in the fetched list, pick a sensible default:
                // prefer "sonnet" (Anthropic), "flash" (Google), "mini" (OpenAI); else first.
                switch provider {
                case .anthropic:
                    if !models.contains(where: { $0.id == claudeModel }) {
                        claudeModel = models.first(where: { $0.id.contains("sonnet") })?.id ?? models.first!.id
                    }
                case .google:
                    if !models.contains(where: { $0.id == googleChatModel }) {
                        googleChatModel = models.first(where: { $0.id.contains("flash") })?.id ?? models.first!.id
                    }
                case .openai:
                    if !models.contains(where: { $0.id == openAIChatModel }) {
                        openAIChatModel = models.first(where: { $0.id.contains("mini") })?.id ?? models.first!.id
                    }
                }
            }
        }
    }

    /// The model currently active for chat (provider-aware).
    var activeChatModel: String {
        switch chatProvider {
        case .anthropic: return claudeModel
        case .google:    return googleChatModel
        case .openai:    return openAIChatModel
        }
    }
```
Lines 251–254, inside `private init()`:
```swift
        if let v = ud.string(forKey: "chatProvider"), let p = ChatProvider(rawValue: v) { chatProvider = p }
        if let v = ud.string(forKey: "googleChatModel"), !v.isEmpty { googleChatModel = v }
        if let v = ud.string(forKey: "openAIChatModel"), !v.isEmpty { openAIChatModel = v }
```
Rest of the file: unrelated published state, task list management, hotkey; keep intact.

## Appendix C: ClaudeService.swift, the regions you change
Lines 182–198 (model, key, conversation, system prompt):
```swift
    /// Chosen in Settings; falls back to the default when the field is left empty.
    private var model: String {
        let m = AppState.shared.claudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? AppState.defaultClaudeModel : m
    }

    var apiKey: String? { KeychainStore.shared.get("anthropic-api-key") }

    // Multi-turn conversation messages (for API)
    private var conversationMessages: [[String: Any]] = []

    func clearConversation() {
        conversationMessages = []
    }

    private let systemPrompt = """
    You are Mochi, Louis's personal AI assistant embedded in the notch of his Mac. \
    You have web search access and can help with absolutely anything — research, coding, finding places, recommendations, tasks, questions. \
    Respond in the user's language. Be thorough and complete — use as much detail as the task requires. \
    No markdown formatting (no **, no ##, no bullet dashes). Use plain text with line breaks.
    """
```
Lines 206–212 (start of `chat`):
```swift
    func chat(query: String, context: PromptContext?, state: AppState) async {
        guard state.chatProvider == .anthropic else {
            await chatOpenAICompatible(query: query, context: context, state: state)
            return
        }
        guard let key = apiKey, !key.isEmpty else {
            await showError("API key missing. Open settings.", state: state)
            return
        }
```
Lines 257–270 (start of `chatOpenAICompatible`, the switch to extend):
```swift
    func chatOpenAICompatible(query: String, context: PromptContext?, state: AppState) async {
        let provider = state.chatProvider
        guard provider != .anthropic else { return }
        guard let key = KeychainStore.shared.get(provider.keychainKey), !key.isEmpty else {
            await showError("\(provider.displayName) API key missing. Configure it in Settings.", state: state)
            return
        }

        let baseURL: String
        switch provider {
        case .google:  baseURL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .openai:  baseURL = "https://api.openai.com/v1/chat/completions"
        case .anthropic: return
        }
```
Lines 342–346 (start of `search`):
```swift
    func search(query: String, context: PromptContext?, state: AppState) async {
        guard let key = apiKey, !key.isEmpty else {
            await showError("Anthropic API key missing. Open settings to configure it.", state: state)
            return
        }
```
Lines 450–497 (`handleResult`, to split as D3 says):
```swift
    private func handleResult(_ data: Data, state: AppState) async {
        // Extract text from Anthropic response (may contain tool_use / web_search_tool_result blocks)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            await showError("Unexpected API response.", state: state)
            return
        }

        // Strip markdown code fences if present, then extract JSON object
        let cleanText: String
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            cleanText = String(text[start...end])
        } else {
            cleanText = text
        }

        // Try to parse as our JSON format
        if let resultData = cleanText.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
            let title  = parsed["title"] as? String ?? "Result"
            let note   = parsed["note"] as? String
            var items: [ResultItem] = []
            if let rawItems = parsed["items"] as? [[String: Any]] {
                for item in rawItems.prefix(3) {
                    items.append(ResultItem(
                        label:  item["label"]  as? String ?? "",
                        detail: item["detail"] as? String ?? "",
                        url:    item["url"]    as? String
                    ))
                }
            }
            state.searchResult = SearchResult(title: title, items: items, note: note)
        } else {
            // Fallback: show raw text in 3-line chunks
            let lines = cleanText.components(separatedBy: "\n").filter { !$0.isEmpty }.prefix(3)
            state.searchResult = SearchResult(
                title: "Claude's response",
                items: lines.map { ResultItem(label: $0, detail: "", url: nil) },
                note: nil
            )
        }

        state.stateOverride = nil
        state.view = .result
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
    }

    private func showError(_ message: String, state: AppState) async {
        state.stateOverride = .error
        state.noteMessage = message
        state.view = .note
    }
```
Signatures you call, already in this file or in scope: `ChatMessage(role: .assistant, content: String)`,
`state.chatHistory: [ChatMessage]`, `state.stateOverride`, `state.view`, `state.noteMessage`,
`Notification.Name.triggerEmote`, `BotEmote.happy / .proud`, `PromptContext` with cases
`.window(appName: String, title: String, url: String?)` and `.file(name: String, url: URL?)`
(pattern-match them positionally as the existing code does).

## Appendix D: IslandViewContent.swift, lines 957–964 (the switch you extend)
```swift
                        Button {
                            switch state.chatProvider {
                            case .anthropic: state.claudeModel = model.id
                            case .google:    state.googleChatModel = model.id
                            case .openai:    state.openAIChatModel = model.id
                            }
                            isPresented = false
                            SoundEngine.shared.play("blip")
```
Rest of the file: unrelated views; keep intact. `ModelPickerView` already iterates
`ChatProvider.allCases` for the chips, so the new provider appears there without changes.

## Appendix E: SettingsView.swift, lines 5–7 and 84–122 (the regions you change)
```swift
struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var apiKey: String = KeychainStore.shared.get("anthropic-api-key") ?? ""
```
```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // MARK: API
                GroupBox("Anthropic API") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("API key (sk-ant-…)", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            KeychainStore.shared.set("anthropic-api-key", value: apiKey)
                            statusMessage = "✓ Key saved."
                        }
                        .buttonStyle(.borderedProminent)

                        Divider().padding(.vertical, 2)

                        Picker("Model", selection: $modelChoice) {
                            ForEach(displayModels, id: \.id) { preset in
                                Text(preset.label).tag(preset.id)
                            }
                            Text("Custom…").tag(Self.customModelTag)
                        }
                        .onChange(of: modelChoice) { _, choice in
                            if choice != Self.customModelTag {
                                state.claudeModel = choice
                            } else {
                                applyCustomModel(customModel)
                            }
                        }

                        if modelChoice == Self.customModelTag {
                            TextField("Model ID (e.g. claude-sonnet-4-6)", text: $customModel)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: customModel) { _, value in applyCustomModel(value) }
                        }

                        Text("Used by the chat. The list comes from your Anthropic account.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                }
```
`statusMessage` is an existing `@State private var statusMessage: String` in this view.
`Color(hex:)` exists in the project. Rest of the file: other GroupBoxes and hook installers;
keep intact.

## Appendix F: ClaudeCodeCLI.swift, create verbatim at build/coucou/NotchBuddy/Sources/App/
```swift
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
        ("default", "Default (your Claude Code setting)"),
        ("opus",    "Opus"),
        ("sonnet",  "Sonnet"),
        ("haiku",   "Haiku"),
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
```

## Appendix G: the headless CLI contract (verified 2026-10-02 on this machine; do not re-run)
- `claude -p "<prompt>" --output-format json` prints one JSON object:
  `{"type":"result","subtype":"success","is_error":false,"result":"<answer>","session_id":"<uuid>",...}`.
  On failure `is_error` is true and `result` carries the message, for example
  `"Not logged in · Please run /login"`.
- `--resume <session_id>` continues that conversation; the same `session_id` comes back.
- `--append-system-prompt <text>`, `--allowedTools <comma list>`, `--add-dir <path>`,
  `--model <opus|sonnet|haiku|full id>` are all accepted by this version.
- The child needs `HOME` and `USER` (or `LOGNAME`) in its environment to find the Keychain login.
  With only `HOME` and `PATH` it reports "Not logged in". With `USER` added it answers normally.
- A one-word answer takes about 5–10 s; the default 120 s timeout is generous on purpose.
