#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/hooks-check.sh [--backup [--force]]

Inspect the Claude Code hooks in settings.json and report which events carry
Coucou hooks. Read-only unless --backup is given.

  --backup  copy settings.json to settings.json.pre-coucou first
  --force   overwrite an existing backup
EOF
}

BACKUP=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --backup) BACKUP=1 ;;
    --force) FORCE=1 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

FILE="$(settings_json)"
[ -f "$FILE" ] || die "settings not found: $FILE"

if [ "$BACKUP" -eq 1 ]; then
  BAK="${FILE}.pre-coucou"
  if [ -e "$BAK" ] && [ "$FORCE" -eq 0 ]; then
    skip "backup exists (use --force to overwrite)"
  else
    cp "$FILE" "$BAK"
    ok "backup written: $BAK"
  fi
fi

python3 - "$FILE" <<'PY'
import json
import sys

path = sys.argv[1]
EVENTS = [
    "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure",
    "SubagentStart", "SubagentStop",
]

try:
    with open(path) as f:
        data = json.load(f)
except ValueError as e:
    print("FAIL: %s is not valid JSON: %s" % (path, e))
    sys.exit(1)

if not isinstance(data, dict):
    data = {}
hooks = data.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}


def hook_list(event):
    out = []
    groups = hooks.get(event)
    if isinstance(groups, list):
        for group in groups:
            if isinstance(group, dict) and isinstance(group.get("hooks"), list):
                out.extend(group["hooks"])
    return [h for h in out if isinstance(h, dict)]


def is_coucou(hook):
    cmd = hook.get("command") or ""
    return "NotchBuddy" in cmd or "nb-hook" in cmd


for event in sorted(hooks.keys()):
    entries = hook_list(event)
    yes = any(is_coucou(h) for h in entries)
    print("%-22s %d  coucou=%s" % (event, len(entries), "yes" if yes else "no"))

known = sum(1 for e in EVENTS if any(is_coucou(h) for h in hook_list(e)))
print("coucou hooks: %d of %d events" % (known, len(EVENTS)))

bad = False
for h in hook_list("PermissionRequest"):
    if is_coucou(h) and h.get("timeout") != 120:
        print("FAIL: PermissionRequest timeout is %s, expected 120" % h.get("timeout"))
        bad = True
if bad:
    sys.exit(1)
PY
