#!/bin/bash
# Install Google Earth Pro on the use.computer macOS sandbox.
# Idempotent: if /Applications/Google Earth Pro.app already exists, skip.
set -eu

APP="/Applications/Google Earth Pro.app"

echo "[install] starting on $(sw_vers -productName) $(sw_vers -productVersion) ($(uname -m))"

if [ -d "$APP" ]; then
  echo "[install] Google Earth Pro already installed, skipping"
  exit 0
fi

# Google Earth Pro for Mac is x86_64 only; Rosetta is required on Apple Silicon.
if [ "$(uname -m)" = "arm64" ]; then
  if ! /usr/bin/pgrep -q oahd; then
    echo "[install] installing Rosetta 2"
    sudo softwareupdate --install-rosetta --agree-to-license
  fi
fi

# Prefer the direct DMG (fastest, most predictable). Fall back to brew cask
# if the URL ever rotates.
DMG_URL="https://dl.google.com/earth/client/advanced/current/GoogleEarthProMac-Intel.dmg"
DMG_PATH="/tmp/GoogleEarthProMac-Intel.dmg"

echo "[install] downloading $DMG_URL"
if ! curl -fL --retry 5 --retry-delay 5 -o "$DMG_PATH" "$DMG_URL"; then
  echo "[install] DMG download failed, trying brew cask fallback"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  if command -v brew >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask google-earth-pro
    [ -d "$APP" ] && { echo "[install] installed via brew cask"; exit 0; }
  fi
  echo "[install] FAILED — neither DMG nor brew worked"
  exit 1
fi

echo "[install] mounting DMG"
MOUNT_POINT=$(hdiutil attach -nobrowse -readonly "$DMG_PATH" | awk -F'\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -1)

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
  echo "[install] FAILED to mount DMG"
  exit 1
fi
echo "[install] mounted at: $MOUNT_POINT"

PKG_FILE=$(find "$MOUNT_POINT" -maxdepth 2 -name "Install Google Earth*.pkg" -type f 2>/dev/null | head -1)
APP_BUNDLE=$(find "$MOUNT_POINT" -maxdepth 2 -name "Google Earth Pro.app" -type d 2>/dev/null | head -1)

if [ -n "$PKG_FILE" ]; then
  echo "[install] running installer: $PKG_FILE"
  sudo installer -pkg "$PKG_FILE" -target /
elif [ -n "$APP_BUNDLE" ]; then
  echo "[install] copying app from $APP_BUNDLE to /Applications"
  sudo ditto "$APP_BUNDLE" "$APP"
else
  echo "[install] FAILED — DMG contains neither installer .pkg nor Google Earth Pro.app"
  ls -la "$MOUNT_POINT"
  hdiutil detach "$MOUNT_POINT" -force || true
  exit 1
fi

hdiutil detach "$MOUNT_POINT" -force || true
rm -f "$DMG_PATH"

# Clear quarantine attributes so Gatekeeper doesn't block first launch.
sudo xattr -dr com.apple.quarantine "$APP" || true

[ -d "$APP" ] && echo "[install] done: $APP" || { echo "[install] FAILED — app not present"; exit 1; }
