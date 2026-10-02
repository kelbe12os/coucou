#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "PASS $1"; }
notok() { FAIL=$((FAIL + 1)); echo "FAIL $1: $2"; }
has() { printf '%s\n' "$1" | grep -qF -- "$2"; }

# 1. syntax
name="syntax"
bad=""
for f in "$REPO"/scripts/*.sh "$REPO/test/run-tests.sh"; do
  bash -n "$f" 2>/dev/null || bad="$bad $f"
done
if [ -z "$bad" ]; then pass "$name"; else notok "$name" "bash -n failed for:$bad"; fi

# 2. executable
name="executable"
bad=""
for f in "$REPO"/scripts/*.sh; do
  [ -x "$f" ] || bad="$bad $f"
done
if [ -z "$bad" ]; then pass "$name"; else notok "$name" "missing executable bit:$bad"; fi

# 3. help
name="help"
bad=""
for f in "$REPO"/scripts/*.sh; do
  out="$("$f" --help 2>&1)" && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$out" | grep -q '^Usage:'; then
    bad="$bad $f"
  fi
done
if [ -z "$bad" ]; then pass "$name"; else notok "$name" "--help not clean for:$bad"; fi

# 4. bad-flag
name="bad-flag"
out="$("$REPO/scripts/verify.sh" --bogus 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 2 ]; then pass "$name"; else notok "$name" "exit $rc, want 2"; fi

# 5. build-check
name="build-check"
out="$("$REPO/scripts/build.sh" --check 2>&1)" && rc=0 || rc=$?
if { [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; } && printf '%s\n' "$out" | grep -qi xcode; then
  pass "$name"
else
  notok "$name" "exit $rc (want 0 or 1) or no xcode mention"
fi

# 6. verify-missing-app
name="verify-missing-app"
out="$("$REPO/scripts/verify.sh" --app "$TMP/Nope.app" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 1 ] && has "$out" "not found"; then pass "$name"; else notok "$name" "exit $rc, want 1"; fi

# 7. verify-hosts
name="verify-hosts"
mkdir -p "$TMP/Fake.app/Contents/MacOS"
printf '%s\n' \
  'https://api.anthropic.com/v1/messages' \
  'https://evil.example.net/x' \
  'com.stablyai.orca' \
  > "$TMP/Fake.app/Contents/MacOS/Coucou"
out="$("$REPO/scripts/verify.sh" --app "$TMP/Fake.app" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 1 ] && has "$out" "evil.example.net"; then pass "$name"; else notok "$name" "exit $rc or no unexpected-host FAIL"; fi

# 8. pi-dry-run
name="pi-dry-run"
out="$(HOME="$TMP/home" "$REPO/scripts/install-pi-extension.sh" --dry-run 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && has "$out" "would install" && [ ! -e "$TMP/home/.pi" ]; then
  pass "$name"
else
  notok "$name" "exit $rc, or .pi was created under the temp HOME"
fi

# 9. pi-roundtrip
name="pi-roundtrip"
reason=""
EXT="$TMP/home/.pi/agent/extensions/coucou-status.ts"
out="$(HOME="$TMP/home" "$REPO/scripts/install-pi-extension.sh" 2>&1)" && rc=0 || rc=$?
{ [ "$rc" -eq 0 ] && [ -f "$EXT" ] && cmp -s "$REPO/pi/coucou-status.ts" "$EXT"; } || reason="install(rc=$rc)"
out="$(HOME="$TMP/home" "$REPO/scripts/install-pi-extension.sh" 2>&1)" && rc=0 || rc=$?
{ [ "$rc" -eq 0 ] && has "$out" "up to date"; } || reason="$reason reinstall(rc=$rc)"
out="$(HOME="$TMP/home" "$REPO/scripts/install-pi-extension.sh" --uninstall 2>&1)" && rc=0 || rc=$?
{ [ "$rc" -eq 0 ] && [ ! -e "$EXT" ]; } || reason="$reason uninstall(rc=$rc)"
if [ -z "$reason" ]; then pass "$name"; else notok "$name" "failed at:$reason"; fi

# 10. hooks-check
name="hooks-check"
reason=""
mkdir -p "$TMP/claude"
CFG="$TMP/claude/settings.json"
write_cfg() {
  python3 - "$CFG" "$1" <<'PY'
import json, sys
path, timeout = sys.argv[1], int(sys.argv[2])
cfg = {"hooks": {
    "PreToolUse": [{"hooks": [{"type": "command", "command": "orca-guard pre", "timeout": 10}]}],
    "PermissionRequest": [{"hooks": [{"type": "command", "command": "/x/NotchBuddy/nb-hook", "timeout": timeout}]}],
}}
with open(path, "w") as f:
    json.dump(cfg, f)
PY
}
write_cfg 120
out="$(CLAUDE_CONFIG_DIR="$TMP/claude" "$REPO/scripts/hooks-check.sh" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ] || ! printf '%s\n' "$out" | grep -qE 'PermissionRequest .* coucou=yes'; then
  reason="timeout120(rc=$rc)"
fi
write_cfg 10
out="$(CLAUDE_CONFIG_DIR="$TMP/claude" "$REPO/scripts/hooks-check.sh" 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || reason="$reason timeout10(rc=$rc)"
printf '{oops\n' > "$CFG"
out="$(CLAUDE_CONFIG_DIR="$TMP/claude" "$REPO/scripts/hooks-check.sh" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 1 ] || ! has "$out" "not valid JSON"; then reason="$reason badjson(rc=$rc)"; fi
if [ -z "$reason" ]; then pass "$name"; else notok "$name" "failed at:$reason"; fi

# 11. uninstall-dry
name="uninstall-dry"
mkdir -p "$TMP/home"
before="$(find "$TMP/home" | LC_ALL=C sort)"
out="$(HOME="$TMP/home" "$REPO/scripts/uninstall.sh" 2>&1)" && rc=0 || rc=$?
after="$(find "$TMP/home" | LC_ALL=C sort)"
if [ "$rc" -eq 0 ] && has "$out" "dry run" && [ "$before" = "$after" ]; then
  pass "$name"
else
  notok "$name" "exit $rc, or the temp HOME changed"
fi

# 12. patch-new-files: the patch must carry its new Swift files (a commit made with -a once dropped one)
name="patch-new-files"
missing=""
for f in ClaudeCodeCLI.swift ZaiPoller.swift UsageViews.swift RelayServer.swift; do
  grep -qE "^\+\+\+ b/NotchBuddy/Sources/App/$f" "$REPO/patches/coucou-orca.patch" || missing="$missing $f"
done
if [ -z "$missing" ]; then pass "$name"; else notok "$name" "patch lacks:$missing"; fi

# 13. extension-harness
name="extension-harness"
SOCK="$TMP/nb.sock"
out="$(COUCOU_SOCKET="$SOCK" "$(bun_bin)" run "$REPO/test/dispatch-harness.ts" "$REPO/pi/coucou-status.ts" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && has "$out" "22 events" && has "$out" "all tags valid for Coucou" && has "$out" "tokens step: tokens"; then
  pass "$name"
else
  notok "$name" "exit $rc; harness output missing '21 events' / 'all tags valid for Coucou'"
fi

echo "tests: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
