#!/bin/bash
# Safari is preinstalled on every macOS image; this hook just verifies
# the bundle exists. Hard-fail if the base image somehow doesn't ship Safari
# (would mean a stripped use.computer image — surface immediately, not later).
set -eu

APP="/Applications/Safari.app"
if [ ! -d "$APP" ]; then
  echo "[install] FAILED — Safari.app not present in /Applications. The use.computer base image is expected to ship Safari preinstalled." >&2
  ls /Applications | head -30 >&2
  exit 1
fi

VERSION=$(/usr/bin/defaults read /Applications/Safari.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo "unknown")
echo "[install] Safari $VERSION present at $APP"
echo "[install] done"
