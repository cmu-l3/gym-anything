#!/bin/bash
# Install the Raycast macOS app on the use.computer macOS sandbox.
# Idempotent: if /Applications/Raycast.app already exists, skip.
#
# Raycast is shipped as a universal-binary DMG (verified via probe 2026-05 \u2014
# `https://www.raycast.com/download` 308-redirects to
# `https://releases.raycast.com/download`, which 302-redirects to a signed
# Cloudflare R2 URL serving `Raycast.dmg` (currently v1.104.17 universal)).
# No Rosetta needed. The DMG contains a drag-and-drop Raycast.app bundle
# (Pattern A from 12_macos_environments.md), not a .pkg installer; the
# script still probes for both shapes so a future vendor switch doesn't
# silently break the install.
set -eu

APP="/Applications/Raycast.app"

echo "[install] starting on $(sw_vers -productName) $(sw_vers -productVersion) ($(uname -m))"

if [ -d "$APP" ]; then
  echo "[install] Raycast already installed at $APP, skipping"
  exit 0
fi

# Universal binary \u2014 Rosetta is NOT required on Apple Silicon. Skip the gate.
# (Kept as a comment for symmetry with google_earth_env which DOES need it.)

DMG_URL_PRIMARY="https://www.raycast.com/download"
DMG_URL_DIRECT="https://releases.raycast.com/download"
DMG_PATH="/tmp/Raycast.dmg"

echo "[install] downloading from $DMG_URL_PRIMARY (follows redirect)"
DOWNLOADED=0
for url in "$DMG_URL_PRIMARY" "$DMG_URL_DIRECT"; do
  if curl -fL --retry 5 --retry-delay 5 --max-time 600 -o "$DMG_PATH" "$url"; then
    DOWNLOADED=1
    echo "[install] downloaded $(wc -c < "$DMG_PATH") bytes from $url"
    break
  fi
  echo "[install] $url failed, trying next"
done

if [ "$DOWNLOADED" -ne 1 ]; then
  echo "[install] DMG download failed for all known URLs, trying brew cask fallback"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  if command -v brew >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask raycast
    [ -d "$APP" ] && { echo "[install] installed via brew cask"; exit 0; }
  else
    echo "[install] brew not present, skipping cask fallback" >&2
  fi
  echo "[install] FAILED \u2014 neither DMG nor brew worked" >&2
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

# Defensive: probe for both .app and .pkg shapes. Raycast ships .app today,
# but vendors flip shapes (Google Earth did) so handle both per
# 12_macos_environments.md.
APP_BUNDLE=$(find "$MOUNT_POINT" -maxdepth 2 -name "Raycast.app" -type d 2>/dev/null | head -1)
PKG_FILE=$(find "$MOUNT_POINT" -maxdepth 2 -name "*.pkg" -type f 2>/dev/null | head -1)

if [ -n "$APP_BUNDLE" ]; then
  echo "[install] copying app from $APP_BUNDLE to /Applications"
  sudo ditto "$APP_BUNDLE" "$APP"
elif [ -n "$PKG_FILE" ]; then
  echo "[install] running installer: $PKG_FILE"
  sudo installer -pkg "$PKG_FILE" -target /
else
  echo "[install] FAILED \u2014 DMG contains neither Raycast.app nor a .pkg" >&2
  ls -la "$MOUNT_POINT" >&2
  hdiutil detach "$MOUNT_POINT" -force || true
  exit 1
fi

hdiutil detach "$MOUNT_POINT" -force || true
rm -f "$DMG_PATH"

# Bypass Gatekeeper first-launch quarantine. The DMG carries the
# com.apple.quarantine xattr; copying preserves it, and unsigned/notarized
# checks will block `open -a Raycast` on the first attempt otherwise.
sudo xattr -dr com.apple.quarantine "$APP" || true

if [ ! -d "$APP" ]; then
  echo "[install] FAILED \u2014 app not present at $APP after install" >&2
  exit 1
fi

VERSION=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")

# Force LaunchServices to register the freshly-installed bundle. Without this,
# `open -a Raycast` immediately after install can fail with "Unable to find
# application named 'Raycast'" because the LS database hasn't picked up the
# new bundle yet. lsregister -f does a synchronous re-scan of one path.
# (Critical finding from specific_env_notes/notion_macos/notes.md.)
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  echo "[install] registering with LaunchServices"
  "$LSREGISTER" -f "$APP" || true
fi

echo "[install] done: $APP (version $VERSION)"
