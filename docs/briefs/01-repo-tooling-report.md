# Report: coucou-orca repo tooling (brief 01-repo-tooling)

## ⚠️ Out-of-scope changes — review required

None. `git status --short --untracked-files=all` lists exactly the new files allowed by Scope:
`README.md`, `scripts/build.sh`, `scripts/hooks-check.sh`, `scripts/install-pi-extension.sh`,
`scripts/lib.sh`, `scripts/uninstall.sh`, `scripts/verify.sh`, `test/run-tests.sh`, plus this
report. `git diff --stat` is empty — no tracked file was modified, and nothing under
`pi/`, `patches/`, `test/dispatch-harness.ts`, `test/live-harness.ts`, `docs/*.html` or
`.gitignore` was touched.

**Environment actions: none.** No container, port, or environment reconfiguration was touched;
no `sudo`, `brew`, `xcodebuild` build, `xcodegen`, `codesign` signing or `ditto` was run by me.
The only commands beyond file writes, git read-only inspection (`status`, `diff`) and the Orca
CLI were the two sanctioned test commands. Inside those tests, `scripts/build.sh --check` ran
the read-only `xcode-select -p` / `xcodebuild -version` probes, and `scripts/verify.sh` ran
read-only `codesign --verify` / `codesign -dv` / `strings` / `stat` against a fake app bundle
inside `$(mktemp -d)` — exactly the scenarios the brief's test spec mandates. Nothing was
written outside `$(mktemp -d)` (temp dirs were cleaned up by the runner's EXIT trap); `~/.pi`,
`~/.claude`, `~/Library` and `/Applications` were not touched.

## Test outcome

`bash test/run-tests.sh` → **12 passed, 0 failed** (exit 0). Final output:

```
PASS syntax
PASS executable
PASS help
PASS bad-flag
PASS build-check
PASS verify-missing-app
PASS verify-hosts
PASS pi-dry-run
PASS pi-roundtrip
PASS hooks-check
PASS uninstall-dry
PASS extension-harness
tests: 12 passed, 0 failed
```

`bash -n scripts/*.sh test/run-tests.sh` → all clean.

Checks skipped: none of the twelve were skipped. (Inside individual script runs, the
environment-dependent sub-checks behaved as designed on this machine: `verify.sh` skips its
runtime-permissions check because `~/Library/Application Support/NotchBuddy/nb.sock` does not
exist, and `build.sh --check` reports FAIL lines for xcode-select/xcodebuild/xcodegen because
only the Command Line Tools are installed — both are expected states, not skips of the test
suite itself.)

## Idempotence proof (from the test output)

- `PASS pi-roundtrip` covers install → reinstall → uninstall: the first install copies
  `pi/coucou-status.ts` and `cmp`s equal; the immediate reinstall prints
  `ok:   up to date: ...` (asserted by the `up to date` substring check) proving the second run
  is a no-op; `--uninstall` then removes exactly that one file.
- `PASS build-check` proves `scripts/build.sh --check` is a stable pure prerequisite probe: it
  exits 0 or 1 (here 1, since Xcode is absent) with `xcode` mentioned, changing nothing on
  disk; running it repeatedly yields the same result. `PASS pi-dry-run` additionally proves
  `--dry-run` writes nothing at all (the temp `$HOME/.pi` is asserted absent afterwards).

## Files touched

| File | Change |
|---|---|
| `scripts/lib.sh` | new — shared helpers + readonly constants |
| `scripts/build.sh` | new — prereqs, clone/patch/build/sign, optional install |
| `scripts/verify.sh` | new — post-build verification of the installed app |
| `scripts/install-pi-extension.sh` | new — install/update/remove the pi extension |
| `scripts/hooks-check.sh` | new — backup + inspect Claude Code hooks |
| `scripts/uninstall.sh` | new — dry-run plan and `--yes` rollback |
| `test/run-tests.sh` | new — the twelve-check suite |
| `README.md` | new — 62 lines, sections per brief |
| `docs/briefs/01-repo-tooling-report.md` | new — this report |

All scripts are executable (`PASS executable`).

## Deviations from the brief

1. **lib.sh direct-execution guard.** The brief specifies lib.sh as sourced-only, but the
   `help` test runs `--help` on every `scripts/*.sh`, which includes lib.sh. Added a guard at
   the top: when executed directly (not sourced) it prints a `Usage:` line and exits 0. No
   effect when sourced.
2. **build.sh creates the parent of `--src` before cloning** (`mkdir -p "$(dirname "$SRC")"`),
   so the default `build/coucou` works on a fresh clone. Additive; git still creates `$SRC`
   itself.
3. **verify.sh check 1 granularity.** "Print ok/FAIL each" was read as one ok/FAIL line per
   sub-assertion: `codesign --verify --strict`, `Identifier=$APP_ID`, and `flags=…adhoc`
   (three lines). The adhoc test greps the flags line per the brief.
4. **verify.sh missing-app path** prints the FAIL line, the `verify: 0 passed, 1 failed, 0
   skipped` summary, then exits 1 — the brief's "end with a summary line" applied literally to
   every exit path.
5. **hooks-check count column** counts individual hooks (commands) per event rather than
   top-level groups; with Coucou's and Orca's one-hook-per-group shape both readings give the
   same numbers. `coucou hooks: N of 12 events` counts only the 12 canonical events listed in
   the brief.
6. **hooks-check.sh dies early** with `FAIL` if `settings.json` itself is absent (the brief
   only specifies behaviour for invalid JSON); the environment guarantees the file exists, so
   no test exercises this.
7. **`--force` without `--backup`** is accepted and ignored rather than rejected; the brief's
   usage shows `--backup [--force]` as nested but does not forbid a lone `--force`.

## Per-test attempt accounting

| Check | Attempts | Notes |
|---|---|---|
| syntax | 1 | |
| executable | 1 | |
| help | 1 | |
| bad-flag | 1 | |
| build-check | 1 | |
| verify-missing-app | 1 | |
| verify-hosts | 1 | |
| pi-dry-run | 1 | |
| pi-roundtrip | 1 | |
| hooks-check | **2** | attempt 1 failed: `hook_list()` in the inline python used `out.extend(h["hooks"] for h in group["hooks"])`, a KeyError that exited 1 on the first invocation; fixed to `out.extend(group["hooks"])` and the full suite reran green |
| uninstall-dry | 1 | |
| extension-harness | 1 | real bun + dispatch-harness + extension, `21 events` and `all tags valid for Coucou` asserted |

## Tests left failing

None.
