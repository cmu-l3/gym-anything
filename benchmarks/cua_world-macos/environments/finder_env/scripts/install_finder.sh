#!/bin/bash
# Finder is the macOS shell — preinstalled in every image, always running.
# This hook verifies the bundle exists at the canonical system path and
# hard-fails otherwise (a stripped image would mean every macOS UI primitive
# is broken — surface immediately, not later).
#
# Note: Finder lives in /System/Library/CoreServices/ — NOT /Applications/
# and NOT /System/Applications/. It's bundled with the OS core, not the
# Applications layer (see 12_macos_environments.md "System Apps Live in
# /System/Applications/" — Finder is even deeper).
set -eu

APP="/System/Library/CoreServices/Finder.app"
if [ ! -d "$APP" ]; then
  echo "[install] FAILED — Finder.app not present at $APP. The use.computer base image must ship Finder; this image looks broken." >&2
  ls /System/Library/CoreServices | head -30 >&2
  exit 1
fi

VERSION=$(/usr/bin/defaults read /System/Library/CoreServices/Finder.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo "unknown")
echo "[install] Finder $VERSION present at $APP"

# Confirm pgrep sees it (Finder should always be running on a healthy image).
if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
  echo "[install] Finder process is running (pid=$(/usr/bin/pgrep -x Finder))"
else
  echo "[install] WARNING — Finder process not running. Starting it." >&2
  /usr/bin/open -a Finder || true
fi

echo "[install] done"
