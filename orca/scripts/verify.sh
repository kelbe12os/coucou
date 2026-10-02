#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/verify.sh [--app <path>]

Verify the installed Coucou app: signature, embedded https hosts against the
allowlist, presence of the Orca patch, and runtime file permissions.
--app overrides the default /Applications/Coucou.app.
EOF
}

APP="$APP_DST"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --app)
      if [ $# -lt 2 ]; then usage >&2; exit 2; fi
      APP="$2"; shift
      ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

P=0
F=0
S=0
vpass() { P=$((P + 1)); ok "$1"; }
vfail() { F=$((F + 1)); fail "$1"; }
vskip() { S=$((S + 1)); skip "$1"; }
summary() { echo "verify: $P passed, $F failed, $S skipped"; }

if [ ! -d "$APP" ]; then
  vfail "$APP not found (run scripts/build.sh --install)"
  summary
  exit 1
fi

BIN="$APP/Contents/MacOS/Coucou"

# Check 1: signature.
if codesign --verify --strict -v "$APP" >/dev/null 2>&1; then
  vpass "codesign --verify --strict"
else
  vfail "codesign --verify --strict failed"
fi
CS_DET="$(codesign -dv "$APP" 2>&1 || true)"
if printf '%s\n' "$CS_DET" | grep -q "^Identifier=$APP_ID"; then
  vpass "Identifier=$APP_ID"
else
  vfail "Identifier missing or wrong (want Identifier=$APP_ID)"
fi
if printf '%s\n' "$CS_DET" | grep -Eq 'flags=.*adhoc'; then
  vpass "signature flags include adhoc"
else
  vfail "signature flags do not include adhoc"
fi

# Checks 2 and 3: binary contents.
if [ ! -f "$BIN" ]; then
  vfail "binary not found: $BIN"
else
  TOTAL=0
  BAD_HOSTS=0
  URLS="$(strings -n 8 "$BIN" | grep -oE 'https?://[A-Za-z0-9./_-]+' | sort -u || true)"
  for url in $URLS; do
    host="${url#*://}"
    host="${host%%/*}"
    TOTAL=$((TOTAL + 1))
    ALLOWED=0
    for suffix in $ALLOWED_HOST_SUFFIXES; do
      if [ "$host" = "$suffix" ] || [ "${host%.$suffix}" != "$host" ]; then
        ALLOWED=1
        break
      fi
    done
    if [ "$ALLOWED" -ne 1 ]; then
      vfail "unexpected host: $host"
      BAD_HOSTS=$((BAD_HOSTS + 1))
    fi
  done
  if [ "$BAD_HOSTS" -eq 0 ]; then
    vpass "$TOTAL hosts, all allowed"
  fi

  N_ORCA="$(strings -n 6 "$BIN" | grep -c 'com.stablyai.orca' || true)"
  if [ "$N_ORCA" -ge 1 ] 2>/dev/null; then
    vpass "Orca allowlist present in binary"
  else
    vfail "Orca allowlist not in binary: unpatched source was built"
  fi
fi

# Check 4: runtime files.
SOCK="$SUPPORT_DIR/nb.sock"
if [ ! -e "$SOCK" ]; then
  vskip "Coucou not running yet; launch it and rerun"
else
  MODE="$(stat -f %Lp "$SOCK" 2>/dev/null || true)"
  if [ "$MODE" = "600" ]; then
    vpass "nb.sock mode 600"
  else
    vfail "nb.sock mode is ${MODE:-unknown}, want 600"
  fi
  MODE="$(stat -f %Lp "$SUPPORT_DIR" 2>/dev/null || true)"
  if [ "$MODE" = "700" ]; then
    vpass "support dir mode 700"
  else
    vfail "support dir mode is ${MODE:-unknown}, want 700"
  fi
  if [ -d "$LOG_DIR" ]; then
    MODE="$(stat -f %Lp "$LOG_DIR" 2>/dev/null || true)"
    if [ "$MODE" = "700" ]; then
      vpass "log dir mode 700"
    else
      vfail "log dir mode is ${MODE:-unknown}, want 700"
    fi
  else
    vskip "log dir does not exist yet: $LOG_DIR"
  fi
fi

summary
if [ "$F" -gt 0 ]; then exit 1; fi
exit 0
