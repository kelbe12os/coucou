#!/bin/sh
# install-remote-hooks.sh — set up a remote machine to report its Claude Code sessions to Coucou.
#
# Run this ON THE REMOTE MACHINE (Git Bash on Windows, or any shell on Linux), from the folder
# that contains nb-hook-remote.sh:
#
#   sh install-remote-hooks.sh --urls "http://<mac-tailnet-name>:6771 http://<mac>.local:6771" --token <token>
#   sh install-remote-hooks.sh --uninstall
#
# What it does:
#   1. Copies nb-hook-remote.sh to ~/.coucou/ and writes ~/.coucou/relay.conf (mode 600).
#   2. Tests the relay with GET /health on each URL and reports which ones answer.
#   3. Merges one hook entry per Claude Code event into ~/.claude/settings.json (backup first),
#      leaving every other entry, such as Orca's, untouched. Needs python3 or PowerShell.
#   --uninstall removes the entries and the files.

set -eu
URLS=""; TOKEN=""; MODE=install
while [ $# -gt 0 ]; do
  case "$1" in
    --urls)  URLS="$2"; shift ;;
    --token) TOKEN="$2"; shift ;;
    --uninstall) MODE=uninstall ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.coucou"
HOOK="$DEST/nb-hook-remote.sh"
CONF="$DEST/relay.conf"
SETTINGS="$HOME/.claude/settings.json"

json_tool() {
  # Windows ships a python3 stub that only opens the Store, so test that it really runs.
  if python3 -c 'import json' >/dev/null 2>&1; then echo python3
  elif command -v powershell.exe >/dev/null 2>&1; then echo powershell
  else echo none; fi
}

merge_hooks() {  # $1 = install|uninstall
  tool=$(json_tool)
  [ "$tool" = none ] && { echo "FAIL: need python3 or PowerShell to edit settings.json" >&2; exit 1; }
  mkdir -p "$HOME/.claude"
  [ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.bak-coucou-$(date +%Y%m%d-%H%M)"
  if [ "$tool" = python3 ]; then
    python3 - "$SETTINGS" "$HOOK" "$1" <<'PY'
import json, sys
path, hook, mode = sys.argv[1], sys.argv[2], sys.argv[3]
events = [("SessionStart",10),("SessionEnd",10),("UserPromptSubmit",10),("PreToolUse",10),
          ("PostToolUse",10),("PostToolUseFailure",10),("PermissionRequest",120),("Notification",10),
          ("Stop",10),("StopFailure",10),("SubagentStart",10),("SubagentStop",10)]
s = json.load(open(path))
hooks = s.setdefault("hooks", {})
def ours(g): return any("nb-hook-remote" in (h.get("command") or "") for h in (g.get("hooks") or []))
for ev, t in events:
    groups = [g for g in (hooks.get(ev) or []) if not ours(g)]
    if mode == "install":
        groups.append({"hooks": [{"type": "command", "command": 'sh "%s"' % hook, "timeout": t}]})
    if groups: hooks[ev] = groups
    else: hooks.pop(ev, None)
if not hooks: s.pop("hooks", None)
json.dump(s, open(path, "w"), indent=2, sort_keys=True); open(path, "a").write("\n")
print("settings.json updated (%s)" % mode)
PY
  else
    powershell.exe -NoProfile -NonInteractive -Command "
\$path = '$SETTINGS'; \$hook = '$HOOK'; \$mode = '$1'
\$s = Get-Content -Raw \$path | ConvertFrom-Json
if (-not \$s.hooks) { \$s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
\$events = @(@('SessionStart',10),@('SessionEnd',10),@('UserPromptSubmit',10),@('PreToolUse',10),@('PostToolUse',10),@('PostToolUseFailure',10),@('PermissionRequest',120),@('Notification',10),@('Stop',10),@('StopFailure',10),@('SubagentStart',10),@('SubagentStop',10))
foreach (\$e in \$events) {
  \$ev = \$e[0]; \$t = \$e[1]
  \$groups = @(); if (\$s.hooks.PSObject.Properties[\$ev]) { \$groups = @(\$s.hooks.\$ev | Where-Object { -not (\$_.hooks | Where-Object { \$_.command -like '*nb-hook-remote*' }) }) }
  if (\$mode -eq 'install') { \$groups += [pscustomobject]@{ hooks = @([pscustomobject]@{ type='command'; command=('sh \"' + \$hook + '\"'); timeout=\$t }) } }
  if (\$s.hooks.PSObject.Properties[\$ev]) { \$s.hooks.PSObject.Properties.Remove(\$ev) }
  if (\$groups.Count -gt 0) { \$s.hooks | Add-Member -NotePropertyName \$ev -NotePropertyValue \$groups }
}
\$s | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 \$path
Write-Output ('settings.json updated (' + \$mode + ')')"
  fi
}

if [ "$MODE" = uninstall ]; then
  merge_hooks uninstall
  rm -f "$HOOK" "$CONF"
  echo "removed $HOOK and $CONF"
  exit 0
fi

[ -n "$URLS" ] && [ -n "$TOKEN" ] || { echo "usage: $0 --urls \"<url> [<url>…]\" --token <token>" >&2; exit 2; }
[ -f "$HERE/nb-hook-remote.sh" ] || { echo "FAIL: nb-hook-remote.sh not next to this script" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "FAIL: curl not found" >&2; exit 1; }

mkdir -p "$DEST"
cp "$HERE/nb-hook-remote.sh" "$HOOK"; chmod 755 "$HOOK"
printf 'COUCOU_RELAY_URLS="%s"\nCOUCOU_RELAY_TOKEN="%s"\n' "$URLS" "$TOKEN" > "$CONF"; chmod 600 "$CONF"
echo "ok:   wrote $HOOK and $CONF"

ok=0
for base in $URLS; do
  if out=$(curl -sS -m 5 --connect-timeout 3 -H "Authorization: Bearer $TOKEN" "$base/health" 2>/dev/null) && printf '%s' "$out" | grep -q '"ok":true'; then
    echo "ok:   $base answers"; ok=1
  else
    echo "skip: $base did not answer (fine if that network is not reachable right now)"
  fi
done
[ "$ok" = 1 ] || echo "warn: no relay URL answered; hooks are installed anyway and will work once one does"

merge_hooks install
echo "done. New Claude Code sessions on this machine report to Coucou; sessions already running keep their old hook set until restarted."
