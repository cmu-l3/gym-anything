#!/bin/bash
# Apple Notes is preinstalled on every macOS image; this hook just verifies
# the bundle exists. On macOS 15 the bundle lives at /System/Applications/Notes.app
# (no /Applications/Notes.app symlink in the use.computer base-macos image, despite
# what some docs imply). We check both paths and prefer whichever exists.
# Hard-fail only if neither is present (would mean a stripped image).
set -eu

APP=""
for candidate in /Applications/Notes.app /System/Applications/Notes.app; do
  if [ -d "$candidate" ]; then
    APP="$candidate"
    break
  fi
done

if [ -z "$APP" ]; then
  echo "[install] FAILED — Notes.app not present in /Applications or /System/Applications. The use.computer base image is expected to ship Apple Notes preinstalled." >&2
  ls /Applications | head -30 >&2
  ls /System/Applications | head -30 >&2
  exit 1
fi

VERSION=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
echo "[install] Apple Notes $VERSION present at $APP"
echo "[install] done"
