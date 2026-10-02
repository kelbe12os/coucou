# coucou-orca

Build [Coucou](https://github.com/Louis-CFM/coucou) from source with an Orca-aware patch, and
report pi worker progress to it.

## What this is

Coucou is an open-source macOS notch companion that shows live Claude Code sessions. The source
of truth for this fork is the `orca` branch of https://github.com/kelbe12os/coucou (upstream
Louis-CFM/coucou plus our commits, merged with upstream main); this repo holds the tooling that
builds and installs it, the pi extension, the remote relay scripts and the docs. The Orca patch
(`patches/coucou-orca.patch`) teaches that build to accept Orca terminal panes as a Claude Code
host, so sessions running inside Orca show up like any other, names the idle slot after Orca,
and adds a chat provider that runs the local `claude -p` so the notch chat works through your
Claude Code login with no API key. The pi extension
(`pi/coucou-status.ts`) reports pi worker progress to Coucou over its local socket, so
dispatched pi agents appear in the notch while they run. `docs/rebuild-plan.html` is the full
plan and audit; `docs/wireframe.html` is the UI walkthrough.

## Layout

```
scripts/                     build.sh, verify.sh, install-pi-extension.sh, hooks-check.sh,
                             uninstall.sh; lib.sh holds shared helpers
patches/coucou-orca.patch    derived: the fork's diff against upstream (scripts/export-patch.sh)
scripts/export-patch.sh      regenerate that patch from the fork checkout
pi/coucou-status.ts          the pi extension (installed to ~/.pi/agent/extensions/)
test/run-tests.sh            test suite; runs on any Mac, no Xcode needed
test/dispatch-harness.ts     synthetic 21-event test of the extension (bun)
test/live-harness.ts         drives a real pi run against a stand-in socket (manual)
docs/rebuild-plan.html       the full plan
docs/widgets-guide.md        how to add tabs and widgets to the island
scripts/remote/              hook relay + installer for Claude Code on other machines
docs/wireframe.html          UI walkthrough
docs/briefs/                 briefs and worker reports
build/                       source checkout created by build.sh (gitignored)
```

## Quick start

1. Install Xcode 16 or later from the App Store and open it once, then:
   `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -license accept`,
   and `brew install xcodegen`.
2. `scripts/build.sh --check` — confirm the prerequisites.
3. `scripts/build.sh --install` — clone the fork's `orca` branch, build, adhoc-sign and install Coucou.app.
4. `scripts/verify.sh` — check the installed app (signature, host allowlist, patch, runtime
   files).
5. `scripts/hooks-check.sh --backup`, then turn on the Claude Code hooks in Coucou's own
   settings (Coucou Settings → Claude Code), then `scripts/hooks-check.sh` to confirm all 12
   events.
6. `scripts/install-pi-extension.sh` — install the pi extension for future pi processes.
7. Other machines: Settings → Remote sessions, enable and copy the token; on the remote run
   `scripts/remote/install-remote-hooks.sh --urls "http://<mac-tailnet-name>:6771 …" --token <token>`.
8. Chat: open the island, click the speech bubble. The provider defaults to Claude Code
   (Settings → "Claude Code (local)" shows the detected binary). An Anthropic key is optional.

## Updating from upstream

The fork's `orca` branch is a normal git branch, so new upstream features arrive by merging:

```
cd ~/Workspaces/Code/coucou          # clone of the fork, remote "upstream" = Louis-CFM/coucou
git fetch upstream && git merge upstream/main   # resolve conflicts if any, build to check
git push origin orca
cd ~/Workspaces/Code/coucou-orca && scripts/build.sh --install && scripts/verify.sh && scripts/export-patch.sh
```

Changes to the app go into the fork as commits; `scripts/export-patch.sh` keeps the patch file
here as a readable summary of everything the fork changes.

## Tests

`bash test/run-tests.sh` — twelve checks covering every script plus a synthetic run of the
extension through `test/dispatch-harness.ts`. It needs no Xcode, no installed app and no running
Coucou. `test/live-harness.ts` is manual: it spawns a real pi with the extension loaded and
captures what the extension sends to a stand-in socket. It needs network access and a model, for
example `COUCOU_SOCKET=/tmp/t.sock PI_MODEL=zai/glm-5.3 bun run test/live-harness.ts pi/coucou-status.ts`.

## Rollback

`scripts/uninstall.sh` prints the plan; `scripts/uninstall.sh --yes` applies it (restores the
settings backup, removes the pi extension, the app and its data, and lists the one manual
System Settings step).

## Status

As of 2026-10-02 evening, built, installed and verified on this Mac: Orca sessions show in the
notch, hooks are installed, the pi extension is live, and chat runs through the local Claude Code CLI.
