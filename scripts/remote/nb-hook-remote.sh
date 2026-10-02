#!/bin/sh
# nb-hook-remote.sh — Claude Code hook relay for machines other than the Mac running Coucou.
#
# Claude Code pipes the hook payload (one JSON object) to stdin. This script forwards it to
# Coucou's HTTP relay and, for PermissionRequest, translates the decision back into the JSON
# Claude Code expects on stdout. It always exits 0 and never blocks a session when Coucou is
# unreachable: non-permission events give up after a few seconds, permission events fall back
# to the terminal prompt.
#
# Runs under Git Bash on Windows (what Claude Code uses for hooks there) and any POSIX sh on
# Linux. Needs curl. Uses python3 or PowerShell when present to carry Claude's suggested
# permission rules for "Always"; without either, "Always" degrades to a one-time "Allow".
#
# Config: ~/.coucou/relay.conf (written by install-remote-hooks.sh), shell syntax:
#   COUCOU_RELAY_URLS="http://<mac-tailnet-name>:6771 http://<mac-hostname>.local:6771"
#   COUCOU_RELAY_TOKEN="…"
# The first URL that answers wins; order them tailnet first, LAN second.

CONF="${COUCOU_RELAY_CONF:-$HOME/.coucou/relay.conf}"
[ -r "$CONF" ] && . "$CONF"
[ -z "$COUCOU_RELAY_URLS" ] || [ -z "$COUCOU_RELAY_TOKEN" ] && exit 0
command -v curl >/dev/null 2>&1 || exit 0

payload=$(cat)
[ -z "$payload" ] && exit 0

# Event name without a JSON parser: the field is a plain string in Claude Code's payloads.
event=$(printf '%s' "$payload" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([A-Za-z]*\)".*/\1/p' | head -n 1)

host=$(hostname 2>/dev/null | cut -d. -f1 | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-' | sed 's/-*$//; s/^-*//')
[ -z "$host" ] && host=remote
host=$(printf '%s' "$host" | cut -c1-24)

# Prepend the relay fields to the object (payload starts with "{").
rest=${payload#\{}
case "$rest" in
  "}"*) body="{\"remote_host\":\"$host\",\"term_program\":\"remote\",\"bundle_id\":\"remote\"$rest" ;;
  *)    body="{\"remote_host\":\"$host\",\"term_program\":\"remote\",\"bundle_id\":\"remote\",$rest" ;;
esac

if [ "$event" = "PermissionRequest" ]; then
  max=118; connect=4
else
  max=4; connect=2
fi

resp=""
for base in $COUCOU_RELAY_URLS; do
  resp=$(printf '%s' "$body" | curl -sS -m "$max" --connect-timeout "$connect" \
          -H "Authorization: Bearer $COUCOU_RELAY_TOKEN" -H "Content-Type: application/json" \
          --data-binary @- "$base/hook" 2>/dev/null) && [ -n "$resp" ] && break
  resp=""
done

[ "$event" = "PermissionRequest" ] || exit 0
[ -z "$resp" ] && exit 0

decision=$(printf '%s' "$resp" | sed -n 's/.*"permissionDecision"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' | head -n 1)

emit_always() {
  # Carry Claude's suggested rules so "Always" persists, when a JSON-capable runtime exists.
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c '
import json, sys
p = json.load(sys.stdin)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest",
  "decision": {"behavior": "allow", "updatedPermissions": p.get("permission_suggestions", [])}}}))' 2>/dev/null && return 0
  fi
  if command -v powershell.exe >/dev/null 2>&1; then
    printf '%s' "$payload" | powershell.exe -NoProfile -NonInteractive -Command '
$p = [Console]::In.ReadToEnd() | ConvertFrom-Json
$s = @(); if ($p.permission_suggestions) { $s = $p.permission_suggestions }
@{ hookSpecificOutput = @{ hookEventName = "PermissionRequest"; decision = @{ behavior = "allow"; updatedPermissions = $s } } } | ConvertTo-Json -Depth 8 -Compress' 2>/dev/null && return 0
  fi
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
}

case "$decision" in
  allow)  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}' ;;
  always) emit_always ;;
  deny)   printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Coucou"}}}' ;;
  *)      : ;;  # "ask", timeout or unknown: print nothing, Claude Code prompts in the terminal
esac
exit 0
