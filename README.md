# coucou-orca

Build [Coucou](https://github.com/Louis-CFM/coucou) from source with an Orca-aware patch, and
report pi worker progress to it.

## What this is

Coucou is an open-source macOS notch companion that shows live Claude Code sessions; this repo
rebuilds it from source at a pinned upstream commit. The Orca patch
(`patches/coucou-orca.patch`) teaches that build to accept Orca terminal panes as a Claude Code
host, so sessions running inside Orca show up like any other. The pi extension
(`pi/coucou-status.ts`) reports pi worker progress to Coucou over its local socket, so
dispatched pi agents appear in the notch while they run. `docs/rebuild-plan.html` is the full
plan and audit; `docs/wireframe.html` is the UI walkthrough.

## Layout

```
scripts/                     build.sh, verify.sh, install-pi-extension.sh, hooks-check.sh,
                             uninstall.sh; lib.sh holds shared helpers
patches/coucou-orca.patch    the Orca patch (applies to upstream commit 8a5c263)
pi/coucou-status.ts          the pi extension (installed to ~/.pi/agent/extensions/)
test/run-tests.sh            test suite; runs on any Mac, no Xcode needed
test/dispatch-harness.ts     synthetic 21-event test of the extension (bun)
test/live-harness.ts         drives a real pi run against a stand-in socket (manual)
docs/rebuild-plan.html       the full plan
docs/wireframe.html          UI walkthrough
docs/briefs/                 briefs and worker reports
build/                       source checkout created by build.sh (gitignored)
```

## Quick start

1. Install Xcode 16 or later from the App Store and open it once, then:
   `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -license accept`,
   and `brew install xcodegen`.
2. `scripts/build.sh --check` — confirm the prerequisites.
3. `scripts/build.sh --install` — clone, patch, build, adhoc-sign and install Coucou.app.
4. `scripts/verify.sh` — check the installed app (signature, host allowlist, patch, runtime
   files).
5. `scripts/hooks-check.sh --backup`, then turn on the Claude Code hooks in Coucou's own
   settings (Coucou Settings → Claude Code), then `scripts/hooks-check.sh` to confirm all 12
   events.
6. `scripts/install-pi-extension.sh` — install the pi extension for future pi processes.

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

As of 2026-10-02, Xcode is not installed on this Mac, so the build step is pending; everything
else is ready.
