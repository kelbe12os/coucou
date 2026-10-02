# Adding tabs and widgets to the island

The island's header has three tabs: home, chat and upload. This guide explains how a tab is
wired, how to add a fourth one with your own widget, and a design for a scriptable widget tab
that needs no rebuild per widget. All paths are inside the upstream checkout the build script
manages, `build/coucou/NotchBuddy/Sources/App/`, on the `orca` branch; every change ends up in
`patches/the fork.patch` and is rebuilt with `scripts/build.sh --install`.

Line numbers below are from the fork at the time of writing (2026-10-02) and drift as the patch
grows; search for the quoted code instead of trusting the numbers.

## 1. How a tab works

A tab is three things, all small.

| Piece | File | What it is |
|---|---|---|
| A view id | `IslandTypes.swift`, `enum IslandView` (line 11) | One case per screen the island can show: `overview, empty, approval, … upload, uploading, choose, mail, prompt, …` |
| A layout entry | `IslandTypes.swift`, `IslandConst.viewLayouts` (line 144) | Height of the island for that view, where Mochi sits, and whether the right panel shows pills |
| A SwiftUI view | `IslandViewContent.swift`, the `switch view` at the top (line 10) | The content drawn inside the island for that case |

The header buttons live in `IslandRootView.swift` around line 472:

```swift
TabButton(icon: "house.fill",       view: .overview, state: state)
TabButton(icon: "bubble.left.fill", view: .prompt,   state: state, preAction: { … })
TabButton(icon: "plus",             view: .upload,   state: state)
```

`TabButton` (same file, line 512) takes an SF Symbol name, the `IslandView` to open, and an
optional `preAction` closure that runs before the switch. The chat tab uses `preAction` to grab
window context; most tabs leave it out.

The layout entry decides the geometry. For reference:

```swift
.overview:  ViewLayout(height: 160, botX: 68,  botY: nil, botDiameter: 58, agentMode: .pills),
.upload:    ViewLayout(height: 176, botX: 140, botY: 104, botDiameter: 62, agentMode: .column),
```

- `height` is the island's expanded height in points. Every ordinary view uses 160; upload and
  mail are taller. Keep new tabs at 160 unless they really need more.
- `botX`, `botY`, `botDiameter` place Mochi. `botY: nil` centres vertically. Leave about 108 pt
  of left padding in your content so it clears Mochi, as the existing cards do.
- `agentMode` is `.pills` only for the overview. Use `.column` for a full-width card, or `.none`
  to hide Mochi's companions entirely.

The island is 640 pt wide. A full-width card gives you roughly 500 by 120 pt of content once
Mochi and padding are accounted for.

## 2. Option 1: a fixed widget in Swift

Use this when the widget is one thing you will rarely change. Each change costs a rebuild,
about two minutes. The whole recipe is four edits.

### 2.1 Add the view id

In `IslandTypes.swift`, append a case to `IslandView`:

```swift
case searching, result, note, settings, greeting
case widget
```

### 2.2 Add the layout

In `IslandConst.viewLayouts`, add a line next to `.note:`:

```swift
.widget:    ViewLayout(height: 160, botX: 60,  botY: nil, botDiameter: 50, agentMode: .column),
```

### 2.3 Write the view

Create `WidgetView.swift` in `Sources/App/`. The helpers you can reuse are all in
`IslandViewContent.swift`: `CardBackground(wash:)` for the card itself (washes: `red, green,
pink, amber, cyan, indigo, soft` or `nil`), `PrimaryButton` and `SecondaryButton`, `CodeBlock`,
and `Color(hex:)`. A minimal widget that shows the current git branch of the focused session:

```swift
import SwiftUI

struct WidgetView: View {
    @ObservedObject var state: AppState
    @State private var branch: String = "…"

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 6) {
                Text("Branch")
                    .font(.system(size: 9.5).monospaced())
                    .foregroundColor(Color(hex: "#7F8A9B"))
                Text(branch)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                PrimaryButton("Refresh") { refresh() }
            }
            .padding(.leading, 108)
            .padding(.top, 14)
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let cwd = state.focusTask?.sessionCwd ?? NSHomeDirectory()
        Task.detached {
            let out = Shell.run("/usr/bin/git", ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"])
            await MainActor.run { branch = out.isEmpty ? "no repo" : out }
        }
    }
}
```

`Shell.run` does not exist yet; the process plumbing in `ClaudeCodeCLI.swift` (`execute`) is the
pattern to copy, including the environment and timeout handling. Under Swift 6 strict
concurrency, do the `Process` work inside a detached task and hop back to the main actor to
publish results, as that file does.

Because the project is generated by XcodeGen, a new file is picked up automatically: the build
script runs `xcodegen` before `xcodebuild`.

### 2.4 Wire the switch and the tab

In `IslandViewContent.swift`, add to the `switch view`:

```swift
case .widget:    WidgetView(state: state)
```

In `IslandRootView.swift`, add a fourth button after the plus:

```swift
TabButton(icon: "square.grid.2x2", view: .widget, state: state)
```

Any SF Symbol name works for the icon. Rebuild with `scripts/build.sh --install`, then
`scripts/verify.sh`.

### 2.5 Things that bite

- Every `switch` over `IslandView` must stay exhaustive. The compiler points at each one; the
  known ones are the view switch, `viewLayouts` (a dictionary, so a missing key crashes at
  runtime instead of failing to compile: add the layout entry first), and a few `if view == …`
  checks in `IslandRootView.swift` that you can ignore.
- The island auto-collapses 15 s after the mouse leaves. A widget that must stay visible sets
  `state.isPinned = true` while it is on screen, the way the approval card does, and clears it
  when it goes away.
- Network calls from a view belong in a poller, not in `onAppear`. Copy `ZaiPoller.swift`: a
  `DispatchSourceTimer`, results published on the main actor into `AppState`, a view that only
  reads state.

## 3. Option 2: a scriptable Widgets tab

Use this when you expect to add or change widgets often. Build the tab once; after that a
widget is a file in a folder. This section is a design, not code yet; it is sized for one
worker brief in the style of `docs/briefs/03-usage-card.md`.

### 3.1 Folder and discovery

```
~/Library/Application Support/NotchBuddy/widgets/
  git-branch.sh          # script widget
  orca-workers.py        # script widget
  burndown.html          # web widget
```

Coucou scans the folder at launch and whenever the Widgets tab opens. Executable files are
script widgets; `.html` files are web widgets. Order is alphabetical; a leading `NN-` prefix
sorts them.

### 3.2 Script widget protocol

Coucou runs the script with no arguments, a 5 s timeout, `HOME`, `USER` and a sane `PATH`, and
the focused session's directory as the working directory when there is one. The script prints
one JSON object:

```json
{
  "title": "Workers",
  "lines": ["01 tooling · done", "02 chat · implementing", "03 usage · PLAN?"],
  "color": "#E0A030",
  "refresh": 30,
  "actions": [{"label": "Open Orca", "open": "/Applications/Orca.app"}]
}
```

- `title` and `lines` are required. Lines beyond four are dropped; long lines truncate.
- `color` tints the pill and the title dot. Defaults to the grey used for services.
- `refresh` is seconds between runs while the tab is open, 60 by default, minimum 5. Nothing
  runs while the tab is closed.
- `actions` are up to two buttons. `open` takes a file path or an `https://` URL; nothing else
  is executed from JSON, so a widget cannot run commands through its own output.
- A non-zero exit, a timeout, or invalid JSON shows the widget with a red "error" line
  containing the first 80 characters of stderr. The island never waits on a widget.

A complete script widget in bash:

```sh
#!/bin/sh
# git-branch.sh — branch and dirty count of the focused session's repo
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no repo")
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
printf '{"title":"Git","lines":["%s","%s changed files"],"refresh":15}\n' "$branch" "$dirty"
```

### 3.3 Web widget

An `.html` file is shown in a `WKWebView` filling the card, loaded from disk with JavaScript
enabled and network allowed. It is the escape hatch for charts and anything the four-line
format cannot express. Keep pages dark-themed and sized for 500 by 120 pt; the card does not
scroll. Coucou reloads the page each time the tab opens.

### 3.4 How it looks

The Widgets tab reuses the overview layout: the focused widget fills the left card with its
title, lines and action buttons; the other widgets are pills on the right, exactly as agents are
today, and clicking a pill swaps focus. One widget only means a full-width card. Script widgets
get a small refresh countdown in the card corner.

### 3.5 What the worker brief would contain

- `IslandView.widgets` plus its layout entry and switch case.
- `WidgetStore.swift`: folder scan, script runner with timeout and the JSON schema above, a
  per-widget timer that runs only while the tab is visible, results published on the main actor.
- `WidgetsView.swift`: the card and pills, a `WKWebView` wrapper for `.html` widgets.
- The `TabButton` line with an icon such as `square.grid.2x2`.
- Two example widgets copied into the folder on first launch if it is empty: the git one above
  and an Orca workers list built on `orca orchestration worker-list --json`.
- Scope, no-discovery and protocol sections as in the previous briefs; acceptance is a green
  build plus the two example widgets rendering, which the coordinator verifies after install.

## 4. Which to pick

| | Fixed Swift widget | Scriptable Widgets tab |
|---|---|---|
| Time to first widget | 30 min | one worker brief, about an hour |
| Time to the next widget | a rebuild | drop a file |
| Can show | anything SwiftUI can | four lines and two buttons, or an HTML page |
| Can break the island | yes, it is compiled in | no, scripts are sandboxed by timeout and JSON |
| Good for | one thing you look at daily | a rotating set of small boards |

If the first widget you want is a single fixed thing, start with Option 1; it is also a fine way
to learn the view structure before building Option 2.
