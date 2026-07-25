#!/bin/bash
# Preview is preinstalled on every macOS image. Since Catalina, Apple ships
# its first-party system apps under /System/Applications/, while
# /Applications/ holds user-installed apps. Both paths are searchable via
# `open -a Preview` (LaunchServices resolves by bundle ID), but for an
# explicit existence check we must try both. Probed on use.computer dev
# fleet (macOS 15.4.1, 2026-05): Preview lives at /System/Applications/Preview.app,
# while Safari lives at /Applications/Safari.app — Apple is inconsistent.
set -eu

CANDIDATES=(
  "/Applications/Preview.app"
  "/System/Applications/Preview.app"
)

APP=""
for c in "${CANDIDATES[@]}"; do
  if [ -d "$c" ]; then
    APP="$c"
    break
  fi
done

if [ -z "$APP" ]; then
  echo "[install] FAILED — Preview.app not present at any expected path. The use.computer base image is expected to ship Preview preinstalled." >&2
  echo "[install] checked: ${CANDIDATES[*]}" >&2
  ls /Applications | head -30 >&2
  ls /System/Applications | head -30 >&2
  exit 1
fi

VERSION=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
echo "[install] Preview $VERSION present at $APP"
echo "[install] done"
