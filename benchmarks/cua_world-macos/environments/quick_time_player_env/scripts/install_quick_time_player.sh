#!/bin/bash
# QuickTime Player is preinstalled on every macOS image; this hook just
# verifies the bundle exists. Apple ships QuickTime Player under
# /System/Applications/ since Catalina (system app, like Preview/Notes).
# Older docs may still mention /Applications/QuickTime Player.app — probe
# both, prefer whichever exists. Hard-fail if neither — would mean a
# stripped use.computer base image and we should surface that immediately.
set -eu

CANDIDATES=(
  "/Applications/QuickTime Player.app"
  "/System/Applications/QuickTime Player.app"
)

APP=""
for c in "${CANDIDATES[@]}"; do
  if [ -d "$c" ]; then
    APP="$c"
    break
  fi
done

if [ -z "$APP" ]; then
  echo "[install] FAILED — QuickTime Player.app not present at any expected path. The use.computer base image is expected to ship QuickTime Player preinstalled." >&2
  echo "[install] checked: ${CANDIDATES[*]}" >&2
  ls /Applications | head -30 >&2
  ls /System/Applications | head -30 >&2
  exit 1
fi

VERSION=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
echo "[install] QuickTime Player $VERSION present at $APP"
echo "[install] done"
