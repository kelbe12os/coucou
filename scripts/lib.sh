#!/bin/bash
# Shared helpers for the coucou-orca scripts. Source this file; every script does:
#   REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$REPO/scripts/lib.sh"
# Executing this file directly is harmless: it prints a usage note and exits 0.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Usage: source scripts/lib.sh   (shared helpers for the coucou-orca scripts)"
  exit 0
fi

log()  { echo "==> $*"; }
ok()   { echo "ok:   $*"; }
fail() { echo "FAIL: $*" >&2; }
skip() { echo "skip: $*"; }
die()  { fail "$@"; exit 1; }

# need_cmd <cmd> [hint] — print an ok/FAIL line; return 1 (do not exit) when missing.
need_cmd() {
  local cmd="${1:-}"
  local hint="${2:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd found"
    return 0
  fi
  fail "$cmd not found${hint:+; $hint}"
  return 1
}

# bun_bin — print the bun executable path (PATH first, then ~/.bun/bin/bun), or die.
bun_bin() {
  local b
  b="$(command -v bun 2>/dev/null || true)"
  if [ -z "$b" ]; then
    b="$HOME/.bun/bin/bun"
    if [ ! -x "$b" ]; then
      die "bun not found on PATH or at $b"
    fi
  fi
  echo "$b"
}

# settings_json — path of the Claude Code settings file (honours CLAUDE_CONFIG_DIR).
settings_json() {
  echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
}

readonly UPSTREAM_URL="https://github.com/Louis-CFM/coucou.git"
readonly UPSTREAM_REF_DEFAULT="8a5c263"
readonly APP_ID="fr.louisraille.NotchBuddy"
readonly APP_DST="/Applications/Coucou.app"
readonly SUPPORT_DIR="$HOME/Library/Application Support/NotchBuddy"
readonly LOG_DIR="$HOME/Library/Logs/NotchBuddy"
readonly PI_EXT_SRC="$REPO/pi/coucou-status.ts"
readonly PI_EXT_DST="$HOME/.pi/agent/extensions/coucou-status.ts"
readonly ALLOWED_HOST_SUFFIXES="anthropic.com openai.com googleapis.com github.com vercel.com stripe.com resend.com notion.com notion.so cal.com z.ai"
