#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/build.sh [--check] [--install] [--ref <git-ref>] [--src <dir>] [--verbose]

Build Coucou (upstream NotchBuddy) from source with the Orca patch.

  --check      check prerequisites only, then exit (0 ok, 1 not ok)
  --install    also install the built app to /Applications/Coucou.app
  --ref REF    upstream ref to build (default: 8a5c263; e.g. --ref main)
  --src DIR    source checkout dir (default: build/coucou inside this repo)
  --verbose    show full xcodegen/xcodebuild output
EOF
}

CHECK=0
INSTALL=0
VERBOSE=0
REF="$UPSTREAM_REF_DEFAULT"
SRC="$REPO/build/coucou"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --check) CHECK=1 ;;
    --install) INSTALL=1 ;;
    --verbose) VERBOSE=1 ;;
    --ref|--src)
      if [ $# -lt 2 ]; then usage >&2; exit 2; fi
      if [ "$1" = "--ref" ]; then REF="$2"; else SRC="$2"; fi
      shift
      ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

# Step 1: prerequisites (collect every problem before failing).
PROBLEMS=0

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
case "$DEV_DIR" in
  *Xcode.app/Contents/Developer)
    ok "xcode-select: $DEV_DIR"
    ;;
  *)
    fail "xcode-select -p is '${DEV_DIR:-<empty>}', want .../Xcode.app/Contents/Developer"
    fail "Install Xcode from the App Store, open it once, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -license accept"
    PROBLEMS=1
    ;;
esac

XCB="$(xcodebuild -version 2>&1 || true)"
XCB_FIRST="$(printf '%s\n' "$XCB" | head -n 1)"
XCB_OK=0
if printf '%s\n' "$XCB_FIRST" | grep -qE '^Xcode [0-9]+\.'; then
  XCB_MAJOR="${XCB_FIRST#Xcode }"
  XCB_MAJOR="${XCB_MAJOR%%.*}"
  if [ "$XCB_MAJOR" -ge 16 ] 2>/dev/null; then
    ok "xcodebuild: $XCB_FIRST"
    XCB_OK=1
  fi
fi
if [ "$XCB_OK" -ne 1 ]; then
  fail "xcodebuild unusable or older than Xcode 16: $XCB_FIRST"
  fail "Install Xcode from the App Store, open it once, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -license accept"
  PROBLEMS=1
fi

need_cmd xcodegen "brew install xcodegen" || PROBLEMS=1
need_cmd git || PROBLEMS=1

if [ "$CHECK" -eq 1 ]; then
  if [ "$PROBLEMS" -ne 0 ]; then
    exit 1
  fi
  log "prerequisites satisfied"
  exit 0
fi
if [ "$PROBLEMS" -ne 0 ]; then
  die "prerequisites failed (fix the problems above, then rerun)"
fi

# Step 2: source.
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"
  log "clone $UPSTREAM_URL -> $SRC"
  git clone "$UPSTREAM_URL" "$SRC"
else
  log "fetch origin in $SRC"
  git -C "$SRC" fetch --quiet origin
fi
CHECKOUT="$REF"
if git -C "$SRC" rev-parse --verify -q "origin/$REF" >/dev/null 2>&1; then
  CHECKOUT="origin/$REF"
fi
git -C "$SRC" checkout -q -B orca "$CHECKOUT"
log "building at: $(git -C "$SRC" log -1 --format='%h %ad %s' --date=short)"

# Step 3: patch (idempotent).
PATCH="$REPO/patches/coucou-orca.patch"
if git -C "$SRC" apply --check --reverse "$PATCH" >/dev/null 2>&1; then
  ok "patch already applied"
elif git -C "$SRC" apply --check "$PATCH" >/dev/null 2>&1; then
  git -C "$SRC" apply "$PATCH"
  # -A, not -a: the patch creates new source files and those must be in the commit too.
  git -C "$SRC" add -A NotchBuddy/Sources NotchBuddy/Resources NotchBuddy/project.yml
  git -C "$SRC" -c user.name=coucou-orca -c user.email=coucou-orca@local commit -qm "Apply coucou-orca.patch"
  ok "patch applied and committed"
else
  die "patch does not apply at $(git -C "$SRC" rev-parse --short HEAD); upstream moved. See docs/rebuild-plan.html step 02 (apply the three edits by hand) or build with --ref 8a5c263"
fi

# Step 4: build.
run_in() {
  local dir="$1"; shift
  if [ "$VERBOSE" -eq 1 ]; then
    (cd "$dir" && "$@")
  else
    (cd "$dir" && "$@") 2>&1 | tail -n 40
  fi
}

log "xcodegen"
run_in "$SRC/NotchBuddy" xcodegen || die "xcodegen failed"
log "xcodebuild (Release)"
run_in "$SRC/NotchBuddy" xcodebuild \
  -project NotchBuddy.xcodeproj \
  -scheme NotchBuddy \
  -configuration Release \
  -derivedDataPath build \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO || die "xcodebuild failed"

APP="$SRC/NotchBuddy/build/Build/Products/Release/Coucou.app"
[ -d "$APP" ] || die "build product not found: $APP"

# Step 5: sign (adhoc).
log "codesign (adhoc)"
codesign --force --deep --sign - "$APP" || die "codesign failed"
log "built: $APP"

# Step 6: install.
if [ "$INSTALL" -eq 1 ]; then
  osascript -e 'quit app "Coucou"' >/dev/null 2>&1 || true
  rm -rf "$APP_DST"
  ditto "$APP" "$APP_DST" || die "ditto failed"
  log "installed: $APP_DST"
  echo "next: scripts/verify.sh"
fi
