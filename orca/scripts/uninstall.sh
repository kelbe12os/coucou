#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/uninstall.sh [--yes]

Print the uninstall plan, or apply it with --yes. Without --yes nothing is
changed.
EOF
}

YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --yes) YES=1 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

SETTINGS="$(settings_json)"
BAK="${SETTINGS}.pre-coucou"
PLIST="$HOME/Library/Preferences/$APP_ID.plist"

if [ "$YES" -eq 0 ]; then
  cat <<EOF
==> uninstall plan
  1. settings: restore $BAK over $SETTINGS (only if the backup exists)
  2. pi extension: remove $PI_EXT_DST
  3. app and data: quit Coucou, then remove
       $APP_DST
       $SUPPORT_DIR
       $LOG_DIR
       $PLIST
  4. manual: System Settings → Privacy & Security → Automation: remove Coucou
dry run; rerun with --yes to apply
EOF
  exit 0
fi

# 1. settings
if [ -e "$BAK" ]; then
  cp "$BAK" "$SETTINGS"
  ok "restored $SETTINGS from $BAK"
else
  skip "no backup; remove hooks from Coucou Settings → Claude Code"
fi

# 2. pi extension
"$REPO/scripts/install-pi-extension.sh" --uninstall

# 3. app and data
osascript -e 'quit app "Coucou"' >/dev/null 2>&1 || true
for p in "$APP_DST" "$SUPPORT_DIR" "$LOG_DIR" "$PLIST"; do
  if [ -e "$p" ]; then
    rm -rf "$p"
    ok "removed $p"
  else
    skip "not present: $p"
  fi
done

# 4. manual step
echo "manual: System Settings → Privacy & Security → Automation: remove Coucou"
