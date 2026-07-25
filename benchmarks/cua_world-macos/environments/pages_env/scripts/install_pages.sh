#!/bin/bash
# Apple Pages is preinstalled on every macOS image at /Applications/Pages.app;
# this hook just verifies the bundle exists and prints its version. Hard-fail
# if the base image somehow doesn't ship Pages so the divergence surfaces
# immediately instead of later when a task tries to launch it.
set -eu

APP="/Applications/Pages.app"
if [ ! -d "$APP" ]; then
  echo "[install] FAILED \u2014 Pages.app not present in /Applications. The use.computer base-macos image is expected to ship Apple Pages preinstalled (probed live 2026-05 against the dev fleet: Pages 14.5 ships in /Applications)." >&2
  ls /Applications | head -30 >&2
  exit 1
fi

VERSION=$(/usr/bin/defaults read /Applications/Pages.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo "unknown")
BUNDLE_ID=$(/usr/bin/defaults read /Applications/Pages.app/Contents/Info CFBundleIdentifier 2>/dev/null || echo "unknown")
echo "[install] Apple Pages $VERSION ($BUNDLE_ID) present at $APP"
echo "[install] done"
