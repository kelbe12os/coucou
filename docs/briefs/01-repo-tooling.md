# Brief: coucou-orca repo tooling (scripts, tests, README)

## Task
This repository packages a plan to build the open-source macOS app **Coucou** (a notch companion
that shows Claude Code sessions) from source with a small patch so it recognises **Orca** terminal
panes, and a **pi extension** that reports pi worker progress to Coucou. The plan is written up in
`docs/rebuild-plan.html`. Your job is to turn that plan into runnable, idempotent shell scripts, a
test runner, and a README. You do not build the app, do not install anything, and do not change
the patch or the extension.

Build, in this order:
1. `scripts/lib.sh` — shared helpers sourced by every script.
2. `scripts/build.sh` — prerequisites check, clone/patch/build/sign, optional install.
3. `scripts/verify.sh` — post-build checks on the installed app.
4. `scripts/install-pi-extension.sh` — copy the pi extension into pi's extensions folder.
5. `scripts/hooks-check.sh` — back up and inspect `~/.claude/settings.json` hooks.
6. `scripts/uninstall.sh` — the rollback.
7. `test/run-tests.sh` — syntax checks plus behavioural checks that run on this machine today.
8. `README.md` — short, task-oriented, pointing at the plan.

Fully implemented, no stubs, no TODOs.
Rules: write each file as soon as it is drafted, build early (here: run `bash -n` on each script
as soon as it is written, and `bash test/run-tests.sh` as soon as it exists), at most two attempts
per failing test; a test that will not go green in two attempts is left failing and explained in
the report.
Environment rule: do not create, recreate, stop, start or reconfigure any container, and do not
change any port. If the environment is not as described below, stop and ask.
Working-tree rule: never run git stash, reset, checkout, switch, clean or rebase. If you need to
compare with HEAD, use git diff or git show; if you need the tree in another state, ask.
Do not commit. The coordinator reviews and commits.
Machine rule: never run `xcodebuild`, `xcodegen`, `sudo`, `brew`, `codesign` or `ditto` yourself,
never write under `~/.pi`, `~/.claude`, `~/Library` or `/Applications`, and never start `pi` or
`Coucou`. Your scripts may do those things when a human runs them later; your tests must not.
Context rule: run tests with minimal console output (pipe through `tail -n 60`); read only the
region of a file you need, never the whole file twice. What you print and re-read accumulates into
every later turn.

## No discovery
Everything you need is in this brief. Do not run orientation commands (`git log`, `git status`,
`ls`, `find`, `tree`, `docker ps`) and do not open, `cat`, `grep` or `read` any file that appears
in the appendices: they are the current contents. The only files you may open are listed under
"Files you may read". If you believe you need anything else, ask; do not go looking.

## Scope
Allowed to change:
- `scripts/**` (new directory; all files new)
- `test/run-tests.sh` (new)
- `README.md` (new)
- `docs/briefs/01-repo-tooling-report.md` (new; your report)
Not allowed: anything else. In particular do not modify `pi/coucou-status.ts`,
`patches/coucou-orca.patch`, `test/dispatch-harness.ts`, `test/live-harness.ts`, `docs/*.html`,
`.gitignore`. If something is missing, stop and ask.

## Files you may read (not embedded)
- `test/dispatch-harness.ts` — only if the argv/env contract in Appendix C turns out to be wrong.
- `pi/coucou-status.ts` — only the header comment (first 25 lines), if Appendix D is not enough.
Nothing else.

## Build and test commands (only these)
```
bash -n scripts/*.sh test/run-tests.sh
bash test/run-tests.sh 2>&1 | tail -n 60
```
Do not build or test anything else. `shellcheck` is not installed; do not install it.

## Environment
- macOS (Apple silicon), zsh login shell; scripts must target `/bin/bash` (bash 3.2 is the
  system bash: no associative arrays, no `mapfile`, no `${var,,}`; use POSIX-ish bash).
- Repository root: `~/Workspaces/Code/coucou-orca`, a git repo on branch `main`
  with one commit. Layout today:
  ```
  .gitignore                 (ignores build/, node_modules/, .DS_Store)
  docs/rebuild-plan.html     (the plan, human-readable)
  docs/wireframe.html
  docs/briefs/01-repo-tooling.md   (this brief)
  patches/coucou-orca.patch  (git patch, applies to upstream commit 8a5c263)
  pi/coucou-status.ts        (pi extension, final, tested)
  test/dispatch-harness.ts   (synthetic test of the extension; bun)
  test/live-harness.ts       (runs real pi; needs network; NOT part of tests)
  ```
- Tools present: `/bin/bash` 3.2, `git` 2.54, `python3` 3.9.6 at `/usr/bin/python3`,
  `bun` 1.2.8 at `~/.bun/bin/bun` (not necessarily on PATH in non-login shells:
  resolve it as `command -v bun || echo "$HOME/.bun/bin/bun"`).
- Tools **absent** on this machine today: Xcode (`xcode-select -p` prints
  `/Library/Developer/CommandLineTools`), `xcodegen`, `shellcheck`. The Coucou app is not
  installed, its socket `~/Library/Application Support/NotchBuddy/nb.sock` does not exist.
  Your tests must pass in exactly this state.
- `~/.pi/agent/extensions/` exists and contains three files owned by Orca
  (`orca-agent-status.ts`, `orca-prefill.ts`, `orca-titlebar-spinner.ts`). Scripts must never
  touch those.
- `~/.claude/settings.json` exists, is valid JSON, and already contains a `hooks` object with
  13 events, each holding one entry whose command belongs to Orca. No Coucou hooks are present.

## Design (binding)

### Conventions for every script
- Shebang `#!/bin/bash`, then `set -euo pipefail`.
- Resolve the repo root as `REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` and
  `source "$REPO/scripts/lib.sh"`.
- `-h`/`--help` prints a usage block and exits 0. Unknown flags: usage to stderr, exit 2.
- Output: one line per step, prefixed `==>` for actions, `ok:` / `FAIL:` / `skip:` for checks.
  Never interactive; never `read` from the terminal.
- Exit codes: 0 success, 1 a check failed or an action could not be done, 2 bad usage.
- Mark every script executable (`chmod +x`).

### scripts/lib.sh (sourced, no shebang execution needed, still `#!/bin/bash` first line)
Functions:
- `log()`   → `echo "==> $*"`
- `ok()`    → `echo "ok:   $*"`
- `fail()`  → `echo "FAIL: $*" >&2`
- `skip()`  → `echo "skip: $*"`
- `die()`   → `fail "$@"; exit 1`
- `need_cmd <cmd> <hint>` → ok/fail line; returns 1 if missing (does not exit).
- `bun_bin()` → prints the bun path: `command -v bun` or `$HOME/.bun/bin/bun`; dies if neither.
- `settings_json()` → prints `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`.
Constants (readonly):
- `UPSTREAM_URL="https://github.com/Louis-CFM/coucou.git"`
- `UPSTREAM_REF_DEFAULT="8a5c263"` (the audited commit; `--ref main` overrides)
- `APP_ID="fr.louisraille.NotchBuddy"`
- `APP_DST="/Applications/Coucou.app"`
- `SUPPORT_DIR="$HOME/Library/Application Support/NotchBuddy"`
- `LOG_DIR="$HOME/Library/Logs/NotchBuddy"`
- `PI_EXT_SRC="$REPO/pi/coucou-status.ts"`, `PI_EXT_DST="$HOME/.pi/agent/extensions/coucou-status.ts"`
- `ALLOWED_HOST_SUFFIXES` as a space-separated string:
  `anthropic.com openai.com googleapis.com github.com vercel.com stripe.com resend.com notion.com notion.so cal.com`

### scripts/build.sh
Usage: `scripts/build.sh [--check] [--install] [--ref <git-ref>] [--src <dir>] [--verbose]`
- `SRC` default `$REPO/build/coucou` (inside the gitignored `build/`). `REF` default
  `UPSTREAM_REF_DEFAULT`.
- Step 1, prerequisites (always run; collect all problems, then exit 1 if any):
  - `xcode-select -p` must end in `Xcode.app/Contents/Developer`; otherwise FAIL with the hint:
    `Install Xcode from the App Store, open it once, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -license accept`
  - `xcodebuild -version` first line `Xcode N.N`, N ≥ 16; FAIL otherwise. If `xcodebuild` itself
    errors (as it does with only the Command Line Tools), report it as the same failure, once.
  - `command -v xcodegen`; hint `brew install xcodegen`.
  - `command -v git`.
  With `--check`: stop after step 1 (exit 0 if all ok, 1 otherwise).
- Step 2, source: if `$SRC/.git` is missing, `git clone "$UPSTREAM_URL" "$SRC"`; else
  `git -C "$SRC" fetch --quiet origin`. Then `git -C "$SRC" checkout -q -B orca "$REF"`
  (if `$REF` is a branch name like `main`, use `origin/$REF`). Print the resolved commit:
  `git -C "$SRC" log -1 --format='%h %ad %s' --date=short`.
- Step 3, patch (idempotent): `PATCH="$REPO/patches/coucou-orca.patch"`.
  If `git -C "$SRC" apply --check --reverse "$PATCH"` succeeds → `ok: patch already applied`.
  Else if `git -C "$SRC" apply --check "$PATCH"` succeeds → `git apply` it and
  `git -C "$SRC" -c user.name=coucou-orca -c user.email=coucou-orca@local commit -qam "Accept Orca panes as a Claude Code host"`.
  Else → die: `patch does not apply at <commit>; upstream moved. See docs/rebuild-plan.html step 02 (apply the three edits by hand) or build with --ref 8a5c263`.
- Step 4, build: `cd "$SRC/NotchBuddy" && xcodegen` then exactly
  ```
  xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release \
    -derivedDataPath build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  ```
  Pipe both through `tail -n 40` unless `--verbose`; preserve the exit status (`set -o pipefail`
  is already on). `APP="$SRC/NotchBuddy/build/Build/Products/Release/Coucou.app"`; die if absent.
- Step 5, sign: `codesign --force --deep --sign - "$APP"`; then `log "built: $APP"`.
- Step 6, only with `--install`: `osascript -e 'quit app "Coucou"' >/dev/null 2>&1 || true`;
  `rm -rf "$APP_DST"`; `ditto "$APP" "$APP_DST"`; `log "installed: $APP_DST"`;
  then print `next: scripts/verify.sh`.
- Never calls `sudo`.

### scripts/verify.sh
Usage: `scripts/verify.sh [--app <path>]`, default `$APP_DST`.
- If the app is missing → `FAIL: <path> not found (run scripts/build.sh --install)`, exit 1.
- Check 1, signature: `codesign --verify --strict -v "$APP"` must succeed; `codesign -dv "$APP" 2>&1`
  must contain `Identifier=$APP_ID` and the word `adhoc` in the flags line. Print ok/FAIL each.
- Check 2, hosts: `strings -n 8 "$APP/Contents/MacOS/Coucou" | grep -oE 'https?://[A-Za-z0-9./_-]+' | sort -u`;
  for each URL take the host (strip scheme and path); it passes if it equals or ends with
  `.<suffix>` for some suffix in `ALLOWED_HOST_SUFFIXES`. Print every unexpected host as FAIL.
  Print `ok: N hosts, all allowed` otherwise.
- Check 3, patch present: `strings -n 6 <binary> | grep -c 'com.stablyai.orca'` must be ≥ 1;
  FAIL text `Orca allowlist not in binary: unpatched source was built`.
- Check 4, runtime (SKIP if `$SUPPORT_DIR/nb.sock` does not exist, with text
  `Coucou not running yet; launch it and rerun`): socket mode must be `600`
  (`stat -f %Lp`), `$SUPPORT_DIR` and `$LOG_DIR` mode `700` (LOG_DIR may not exist yet → skip
  that one).
- End with a summary line `verify: P passed, F failed, S skipped`; exit 1 if F > 0.

### scripts/install-pi-extension.sh
Usage: `scripts/install-pi-extension.sh [--dry-run] [--uninstall]`
- Install: `mkdir -p "$(dirname "$PI_EXT_DST")"`. If `$PI_EXT_DST` exists and
  `cmp -s` says identical → `ok: up to date: $PI_EXT_DST`, exit 0. If it exists and differs →
  print `diff -u "$PI_EXT_DST" "$PI_EXT_SRC" || true` then copy. If absent → copy.
  Copy = `cp "$PI_EXT_SRC" "$PI_EXT_DST"`. After copying print
  `ok: installed $PI_EXT_DST (next pi you start loads it; running pi processes do not)`.
- `--dry-run`: print exactly what would happen (`would install`, `would update`, `up to date`,
  `would remove`, `nothing to remove`) and exit 0 without writing.
- `--uninstall`: `rm -f "$PI_EXT_DST"` if present; print ok either way. Never touch other files.

### scripts/hooks-check.sh
Usage: `scripts/hooks-check.sh [--backup [--force]]`
- `--backup`: copy `settings_json()` to `<same dir>/settings.json.pre-coucou`. If the backup
  already exists and `--force` is absent → `skip: backup exists (use --force to overwrite)`.
- Always (after any backup): run an inline `python3 - "$FILE" <<'PY' … PY` that:
  - loads the JSON (on failure print `FAIL: <file> is not valid JSON: <error>` and exit 1),
  - prints one line per hook event, sorted: `<event padded to 22> <count>  coucou=<yes|no>`
    where coucou=yes if any entry under that event has a hook whose `command` contains
    `NotchBuddy` or `nb-hook`,
  - prints `coucou hooks: <N> of 12 events` where the 12 are
    `SessionStart SessionEnd UserPromptSubmit PreToolUse PostToolUse PostToolUseFailure PermissionRequest Notification Stop StopFailure SubagentStart SubagentStop`,
  - if a Coucou PermissionRequest hook exists and its `timeout` is not 120, prints
    `FAIL: PermissionRequest timeout is <t>, expected 120` and exits 1,
  - otherwise exits 0.
- Read-only apart from `--backup`.

### scripts/uninstall.sh
Usage: `scripts/uninstall.sh [--yes]`
- Without `--yes`: print the numbered plan below with the concrete paths and exit 0 without
  changing anything. Last line: `dry run; rerun with --yes to apply`.
- With `--yes`, in this order, each step printing ok/skip:
  1. Settings: if `<dir>/settings.json.pre-coucou` exists → copy it back over
     `settings.json`; else `skip: no backup; remove hooks from Coucou Settings → Claude Code`.
  2. pi extension: `"$REPO/scripts/install-pi-extension.sh" --uninstall`.
  3. App: `osascript -e 'quit app "Coucou"' >/dev/null 2>&1 || true`; `rm -rf "$APP_DST" "$SUPPORT_DIR" "$LOG_DIR" "$HOME/Library/Preferences/$APP_ID.plist"`.
  4. Print the manual step: `System Settings → Privacy & Security → Automation: remove Coucou`.
- Never deletes `settings.json.bak-*` (Coucou's own backups) and never touches `~/.pi` beyond
  step 2.

### test/run-tests.sh
Usage: `bash test/run-tests.sh`. Must pass on this machine in its current state (no Xcode, no
app, no socket). Each check prints `PASS <name>` or `FAIL <name>: <why>`; the script ends with
`tests: P passed, F failed` and exits 1 if F > 0. Never writes outside `$(mktemp -d)`; never
touches `$HOME`. Checks, in order:
1. `syntax`: `bash -n` on every `scripts/*.sh` and `test/run-tests.sh`.
2. `executable`: every `scripts/*.sh` has the executable bit.
3. `help`: every `scripts/*.sh --help` exits 0 and prints a line starting with `Usage:`.
4. `bad-flag`: `scripts/verify.sh --bogus` exits 2.
5. `build-check`: `scripts/build.sh --check` exits 0 or 1 (never anything else) and its output
   mentions `xcode` (case-insensitive). (On this machine it exits 1; do not assert which.)
6. `verify-missing-app`: `scripts/verify.sh --app "$TMP/Nope.app"` exits 1 and prints `not found`.
7. `verify-hosts`: build a fake app in `$TMP`: `mkdir -p "$TMP/Fake.app/Contents/MacOS"`, write
   a file `Coucou` there containing the lines `https://api.anthropic.com/v1/messages`,
   `https://evil.example.net/x` and `com.stablyai.orca` (plain text is fine: `strings` will find
   them). Run `scripts/verify.sh --app "$TMP/Fake.app"`; expect exit 1 and output containing
   `evil.example.net`. (Check 1 will fail on the fake app too; that is fine, this test only
   asserts the host check fires.)
8. `pi-dry-run`: run `HOME="$TMP/home" scripts/install-pi-extension.sh --dry-run`; expect exit 0,
   output containing `would install`, and `$TMP/home/.pi` still absent afterwards.
9. `pi-roundtrip`: with `HOME="$TMP/home"`: install (exit 0, file exists and `cmp`s equal to the
   source), install again (output contains `up to date`), `--uninstall` (file gone).
10. `hooks-check`: write `$TMP/claude/settings.json` with python3 containing a `hooks` object with
    `PreToolUse` → one Orca-like entry and `PermissionRequest` → one entry whose command is
    `"/x/NotchBuddy/nb-hook"` with `timeout: 120`; run
    `CLAUDE_CONFIG_DIR="$TMP/claude" scripts/hooks-check.sh`; expect exit 0 and a line matching
    `PermissionRequest .* coucou=yes`. Then rewrite with `timeout: 10` and expect exit 1.
    Then write invalid JSON and expect exit 1 with `not valid JSON`.
11. `uninstall-dry`: `HOME="$TMP/home" scripts/uninstall.sh` exits 0, prints `dry run`, and
    `$TMP/home` has no new files.
12. `extension-harness`: `SOCK="$TMP/nb.sock"; COUCOU_SOCKET="$SOCK" "$(bun_bin)" run
    "$REPO/test/dispatch-harness.ts" "$REPO/pi/coucou-status.ts"`; capture stdout; PASS iff it
    contains both `21 events` and `all tags valid for Coucou`. (The harness always exits 0; the
    text is the assertion.) Source `scripts/lib.sh` for `bun_bin`.

### README.md
Under 80 lines. Sections: **What this is** (three sentences: Coucou, the Orca patch, the pi
extension; link `docs/rebuild-plan.html` as the full plan and `docs/wireframe.html` as the UI
walkthrough), **Layout** (the tree above plus `scripts/`), **Quick start** (numbered: install
Xcode + xcodegen; `scripts/build.sh --check`; `scripts/build.sh --install`; `scripts/verify.sh`;
`scripts/hooks-check.sh --backup` then install hooks from Coucou Settings then
`scripts/hooks-check.sh`; `scripts/install-pi-extension.sh`), **Tests** (`bash test/run-tests.sh`,
and that `test/live-harness.ts` needs network and a model and is manual), **Rollback**
(`scripts/uninstall.sh`, then `--yes`), **Status** (one line: as of 2026-10-02 Xcode is not
installed on this Mac, so the build step is pending; everything else is ready). Plain Markdown,
no badges, no emoji.

## Tests
`test/run-tests.sh` is the test suite; the twelve checks above are the required scenarios. Fakes
allowed: the fake app bundle, the temporary HOME and CLAUDE_CONFIG_DIR, the temporary socket path.
Must be real: `bash -n`, the real scripts, the real harness run through bun against the real
extension. Nothing may set a variable that changes behaviour in production beyond `HOME`,
`CLAUDE_CONFIG_DIR` and `COUCOU_SOCKET`, which the scripts and the extension already honour.

## Docs (in scope)
Only `README.md` (new, specified above) and your report. Do not edit the HTML docs.

## Self-verify before reporting done
1. Run the two commands under "Build and test commands". At most two attempts per failing test.
   Say which checks were skipped and why.
2. Prove idempotence of `install-pi-extension.sh` and `--check` of `build.sh` from the test
   output (quote the PASS lines).
3. `git status --short` and `git diff --stat`. Compare every touched file against Scope.
   Out-of-scope changes go in a section titled **⚠️ Out-of-scope changes — review required**
   at the TOP of your report: path, one-sentence change, additive or structural, why it was
   necessary. State explicitly whether any environment action was taken.
4. Write the full report to `docs/briefs/01-repo-tooling-report.md`: test outcome with the
   PASS/FAIL count, files touched, out-of-scope changes at the top if any, numbered deviations
   from this brief with reasons, per-test attempt accounting, tests left failing with cause.
   Summarise it in the `worker_done` body and set `--report-path docs/briefs/01-repo-tooling-report.md`.

## If anything is unclear
Ask with `orca orchestration ask --question "<question>" --timeout-ms 1800000`. If it times out,
run `orca orchestration ask --resume <message_id>`. Never guess on: the exit-code contract, the
host allowlist, what the tests may touch on disk, whether a script may call sudo (it may not).
Guess freely on: helper names inside lib.sh, log wording beyond the prefixes, README phrasing.

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
   you decide it, with the reason; tests first green; after any second attempt on a failing test.
3. Inbox (pull). Before each phase change (plan → implement → test → document → report), and
   before you diagnose any failing test, run
   `orca orchestration check --terminal <your handle> --unread --format` and apply any
   coordinator guidance you find before continuing. A failing test is not flaky until you have
   read your inbox: the coordinator may already have found the cause in your code.
4. Questions. Whenever this brief contradicts itself or the code, ask (the command under
   "If anything is unclear"). Do not guess. Do not change containers, ports or environment; ask.
5. Heartbeat every 5 minutes with `--phase`; `worker_done` exactly once, as the injected
   preamble says, with `--outcome succeeded` or `--outcome failed`.

## Appendix A: the plan's commands these scripts wrap (verbatim from docs/rebuild-plan.html)
Prerequisites:
```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -version        # want: Xcode 16 or later
brew install xcodegen
```
Source and patch:
```
git clone https://github.com/Louis-CFM/coucou.git
git checkout -b orca
git apply --check <patch> && git apply <patch>
```
Build:
```
cd NotchBuddy && xcodegen
xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```
Sign and install:
```
codesign --force --deep --sign - "$APP"
rm -rf /Applications/Coucou.app
ditto "$APP" /Applications/Coucou.app
```
Verify:
```
codesign --verify --strict -v /Applications/Coucou.app
codesign -dv /Applications/Coucou.app 2>&1 | grep -E 'Identifier|flags'
strings -n 8 /Applications/Coucou.app/Contents/MacOS/Coucou | grep -oE 'https?://[A-Za-z0-9./_-]+' | sort -u
strings -n 6 /Applications/Coucou.app/Contents/MacOS/Coucou | grep -c 'com.stablyai.orca'
ls -l ~/Library/Application\ Support/NotchBuddy/nb.sock     # want srw-------
```
Rollback:
```
cp ~/.claude/settings.json.pre-coucou ~/.claude/settings.json
rm -f ~/.pi/agent/extensions/coucou-status.ts
osascript -e 'quit app "Coucou"'
rm -rf /Applications/Coucou.app ~/Library/Application\ Support/NotchBuddy ~/Library/Logs/NotchBuddy ~/Library/Preferences/fr.louisraille.NotchBuddy.plist
```

## Appendix B: expected `strings` hosts in a correct build (all allowed)
```
api.anthropic.com  api.openai.com  generativelanguage.googleapis.com  api.github.com  github.com
api.vercel.com  vercel.com  api.stripe.com  dashboard.stripe.com  api.resend.com  resend.com
api.notion.com  notion.so  api.cal.com  app.cal.com
```

## Appendix C: test/dispatch-harness.ts contract (not edited)
- Invocation: `COUCOU_SOCKET=<abs path to a unix socket to create> bun run test/dispatch-harness.ts <abs path to extension .ts>`
- It creates the socket server itself (unlinking a stale file first), loads the extension, fires
  a 21-event synthetic worker dispatch, and prints one line per received event, then:
  ```
  21 events, tag=pi-07-auth-hooks, tagLen=16
  all tags valid for Coucou
  ```
  (or `INVALID TAGS: N`). It always exits 0; assert on the text. Runs in about one second.
- It imports only `net` and `fs`; no network.

## Appendix D: pi/coucou-status.ts, what the scripts need to know (not edited)
- A pi extension (TypeScript, loaded by pi via jiti). Reads env: `COUCOU_SOCKET` (socket path
  override, default `$HOME/Library/Application Support/NotchBuddy/nb.sock`), `COUCOU_AGENT`
  (pill tag override), `COUCOU_DISABLE=1` (off). Writes JSON lines to the socket; never prints;
  never blocks pi.
- Install location is exactly `~/.pi/agent/extensions/coucou-status.ts`; pi loads every `.ts`
  in that directory at process start.

## Appendix E: shape of ~/.claude/settings.json hooks (for hooks-check.sh; real file not embedded)
```json
{
  "hooks": {
    "PreToolUse": [ { "hooks": [ { "type": "command", "command": "<shell …>", "timeout": 10 } ] } ],
    "PermissionRequest": [ { "hooks": [ { "type": "command", "command": "<shell …>", "timeout": 10 } ] } ]
  },
  "model": "…", "permissions": { }, "theme": "…"
}
```
Each event maps to a list of groups; each group has an optional `matcher` and a `hooks` list;
each hook has `type`, `command`, optional `timeout`. Coucou's installer appends one group per
event with a single hook whose command contains the path `…/NotchBuddy/nb-hook` and timeout 10,
except PermissionRequest with timeout 120.
