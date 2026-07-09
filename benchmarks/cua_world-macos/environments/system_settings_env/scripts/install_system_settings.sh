#!/bin/bash
# System Settings (macOS 13+) is preinstalled on every macOS image. Apple
# ships first-party system apps under /System/Applications/ — System Settings
# lives there. We probe both /Applications/ and /System/Applications/ to be
# defensive across image variants (cf. preview_env's install_preview.sh,
# per pattern in 12_macos_environments.md "System Apps Live in
# /System/Applications/, Not /Applications/").
set -eu

CANDIDATES=(
  "/System/Applications/System Settings.app"
  "/Applications/System Settings.app"
  "/System/Applications/System Preferences.app"
  "/Applications/System Preferences.app"
)

APP=""
for c in "${CANDIDATES[@]}"; do
  if [ -d "$c" ]; then
    APP="$c"
    break
  fi
done

if [ -z "$APP" ]; then
  echo "[install] FAILED — System Settings.app not present at any expected path." >&2
  echo "[install] checked: ${CANDIDATES[*]}" >&2
  ls /Applications | head -30 >&2
  ls /System/Applications | head -30 >&2
  exit 1
fi

VERSION=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
BUNDLE_ID=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "unknown")
echo "[install] System Settings $VERSION ($BUNDLE_ID) present at $APP"
echo "[install] done"
