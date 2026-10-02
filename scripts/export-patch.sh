#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/lib.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/export-patch.sh [--src <fork checkout>]

Regenerate patches/coucou-orca.patch from the fork: the diff between the point where the
"orca" branch last merged upstream main and the branch head, limited to the app sources.
Default checkout: build/coucou (what build.sh clones).
USAGE
}

SRC="$REPO/build/coucou"
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --src) [ $# -ge 2 ] || { usage >&2; exit 2; }; SRC="$2"; shift ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done
[ -d "$SRC/.git" ] || die "no checkout at $SRC (run scripts/build.sh first)"
git -C "$SRC" remote get-url upstream >/dev/null 2>&1 || git -C "$SRC" remote add upstream "$ORIGINAL_UPSTREAM_URL"
git -C "$SRC" fetch -q upstream
BASE="$(git -C "$SRC" merge-base upstream/main HEAD)"
git -C "$SRC" diff "$BASE" HEAD -- NotchBuddy/Sources NotchBuddy/Resources NotchBuddy/project.yml > "$REPO/patches/coucou-orca.patch"
log "patch exported: $(grep -c '^diff --git' "$REPO/patches/coucou-orca.patch") files, base $(git -C "$SRC" rev-parse --short "$BASE") (upstream), head $(git -C "$SRC" rev-parse --short HEAD)"
