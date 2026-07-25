#!/bin/bash
# Install the Notion desktop app on the use.computer macOS sandbox.
# Idempotent: if /Applications/Notion.app already exists, skip.
#
# Notion is shipped as a universal-binary DMG (verified via probe 2026-05 —
# `https://www.notion.so/desktop/mac-universal/download` 307-redirects to
# `https://desktop-release.notion-static.com/Notion-*-universal.dmg`).
# No Rosetta needed. The DMG contains a drag-and-drop Notion.app bundle
# (Pattern A from 12_macos_environments.md), not a .pkg installer.
set -eu

APP="/Applications/Notion.app"

echo "[install] starting on $(sw_vers -productName) $(sw_vers -productVersion) ($(uname -m))"

if [ -d "$APP" ]; then
  echo "[install] Notion already installed at $APP, skipping"
  exit 0
fi

# Universal binary — Rosetta is NOT required on Apple Silicon. Skip the check
# (kept here as a comment so the difference vs google_earth_env is explicit).
# if [ "$(uname -m)" = "arm64" ]; then
#   ... Rosetta install ...
# fi

# Prefer the official "latest universal" redirect, then fall back to a brew
# cask. The 307-redirect URL embeds the current version number; honoring
# redirects (-L) means the script doesn't need to know the version ahead.
DMG_URL_PRIMARY="https://www.notion.so/desktop/mac-universal/download"
DMG_URL_LEGACY="https://www.notion.so/desktop/mac/download"
DMG_PATH="/tmp/Notion-universal.dmg"

echo "[install] downloading from $DMG_URL_PRIMARY (follows redirect)"
DOWNLOADED=0
for url in "$DMG_URL_PRIMARY" "$DMG_URL_LEGACY"; do
  if curl -fL --retry 5 --retry-delay 5 --max-time 600 -o "$DMG_PATH" "$url"; then
    DOWNLOADED=1
    echo "[install] downloaded $(wc -c < "$DMG_PATH") bytes from $url"
    break
  fi
  echo "[install] $url failed, trying next"
done

if [ "$DOWNLOADED" -ne 1 ]; then
  echo "[install] DMG download failed for all known URLs, trying brew cask fallback"
  # Source brew shellenv only if brew is actually installed at the expected
  # path; the unconditional eval would noisily fail on a stripped image.
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  if command -v brew >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask notion
    [ -d "$APP" ] && { echo "[install] installed via brew cask"; exit 0; }
  else
    echo "[install] brew not present, skipping cask fallback" >&2
  fi
  echo "[install] FAILED — neither DMG nor brew worked" >&2
  exit 1
fi

echo "[install] mounting DMG"
MOUNT_POINT=$(hdiutil attach -nobrowse -readonly "$DMG_PATH" \
              | awk -F'\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -1)

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
  echo "[install] FAILED to mount DMG" >&2
  exit 1
fi
echo "[install] mounted at: $MOUNT_POINT"

# Defensive: probe for both .app and .pkg shapes. Notion ships .app today,
# but vendors flip shapes (Google Earth did) so handle both per
# 12_macos_environments.md.
APP_BUNDLE=$(find "$MOUNT_POINT" -maxdepth 2 -name "Notion.app" -type d 2>/dev/null | head -1)
PKG_FILE=$(find "$MOUNT_POINT" -maxdepth 2 -name "*.pkg" -type f 2>/dev/null | head -1)

if [ -n "$APP_BUNDLE" ]; then
  echo "[install] copying app from $APP_BUNDLE to /Applications"
  sudo ditto "$APP_BUNDLE" "$APP"
elif [ -n "$PKG_FILE" ]; then
  echo "[install] running installer: $PKG_FILE"
  sudo installer -pkg "$PKG_FILE" -target /
else
  echo "[install] FAILED — DMG contains neither Notion.app nor a .pkg" >&2
  ls -la "$MOUNT_POINT" >&2
  hdiutil detach "$MOUNT_POINT" -force || true
  exit 1
fi

hdiutil detach "$MOUNT_POINT" -force || true
rm -f "$DMG_PATH"

# Bypass Gatekeeper first-launch quarantine. The DMG carries the
# com.apple.quarantine xattr; copying preserves it, and unsigned/notarized
# checks will block `open -a Notion` on the first attempt otherwise.
sudo xattr -dr com.apple.quarantine "$APP" || true

if [ ! -d "$APP" ]; then
  echo "[install] FAILED — app not present at $APP after install" >&2
  exit 1
fi

VERSION=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")

# Force LaunchServices to register the freshly-installed bundle. Without
# this, `open -a Notion` immediately after install can fail with "Unable to
# find application named 'Notion'" because the LS database hasn't picked up
# the new bundle yet. lsregister -f does a synchronous re-scan of one path.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  echo "[install] registering with LaunchServices"
  "$LSREGISTER" -f "$APP" || true
fi

echo "[install] done: $APP (version $VERSION)"
