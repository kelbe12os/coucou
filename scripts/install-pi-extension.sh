#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/install-pi-extension.sh [--dry-run] [--uninstall]

Install the Coucou pi extension (pi/coucou-status.ts) into
~/.pi/agent/extensions/coucou-status.ts. pi loads every .ts file in that
directory at process start, so the next pi you start picks it up.

  --dry-run     print what would happen, change nothing
  --uninstall   remove the extension (never touches other files)
EOF
}

DRY=0
UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$UNINSTALL" -eq 1 ]; then
  if [ -e "$PI_EXT_DST" ]; then
    if [ "$DRY" -eq 1 ]; then
      echo "==> would remove $PI_EXT_DST"
    else
      rm -f "$PI_EXT_DST"
      ok "removed $PI_EXT_DST"
    fi
  else
    if [ "$DRY" -eq 1 ]; then
      skip "nothing to remove"
    else
      ok "nothing to remove"
    fi
  fi
  exit 0
fi

if [ -e "$PI_EXT_DST" ]; then
  if cmp -s "$PI_EXT_SRC" "$PI_EXT_DST"; then
    ok "up to date: $PI_EXT_DST"
  elif [ "$DRY" -eq 1 ]; then
    echo "==> would update $PI_EXT_DST"
  else
    diff -u "$PI_EXT_DST" "$PI_EXT_SRC" || true
    cp "$PI_EXT_SRC" "$PI_EXT_DST"
    ok "installed $PI_EXT_DST (next pi you start loads it; running pi processes do not)"
  fi
  exit 0
fi

if [ "$DRY" -eq 1 ]; then
  echo "==> would install $PI_EXT_DST"
  exit 0
fi

mkdir -p "$(dirname "$PI_EXT_DST")"
cp "$PI_EXT_SRC" "$PI_EXT_DST"
ok "installed $PI_EXT_DST (next pi you start loads it; running pi processes do not)"
