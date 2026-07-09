#!/bin/bash
# Install macFUSE on the use.computer macOS sandbox.
#
# macFUSE ships as a DMG containing a single .pkg installer (Pattern B from
# 12_macos_environments.md). Download the latest stable release from the
# official macfuse/macfuse GitHub repository, mount, and `sudo installer -pkg`.
# Idempotent: if /Library/Filesystems/macfuse.fs already exists, skip.
#
# Notes:
#   - macFUSE is a universal binary (works on both arm64 and x86_64) — no
#     Rosetta required.
#   - The macFUSE kext / system extension requires explicit user approval
#     (System Settings > Privacy & Security + Reduced Security in Recovery
#     Mode on Apple Silicon) to actually load. The use.computer base-macos
#     image cannot satisfy that gesture automatically, so this script
#     installs the macFUSE *bundle* (files on disk + pkg receipt) but does
#     not attempt to load the kext. Tasks audit the installed-on-disk
#     artifacts rather than driving live mounts.
#   - Pinned to a known-good version (4.10.2, released 2025) for
#     reproducibility. The GitHub release URL is structured as
#     macfuse-X.Y.Z.dmg under /releases/download/macfuse-X.Y.Z/.
set -eu

BUNDLE_PATH="/Library/Filesystems/macfuse.fs"

echo "[install] starting on $(sw_vers -productName) $(sw_vers -productVersion) ($(uname -m))"

if [ -d "$BUNDLE_PATH" ]; then
  INSTALLED_VERSION=$(/usr/bin/defaults read "$BUNDLE_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
  echo "[install] macFUSE already installed at $BUNDLE_PATH (version $INSTALLED_VERSION), skipping"
  exit 0
fi

# Pinned: macFUSE 4.10.2 is the most recent stable kext-bridge release in the
# v4 line. The v5 line uses System Extensions but is incompatible with the
# sandbox's security posture; v4 still installs cleanly on disk.
MACFUSE_VERSION="4.10.2"
DMG_URL="https://github.com/macfuse/macfuse/releases/download/macfuse-${MACFUSE_VERSION}/macfuse-${MACFUSE_VERSION}.dmg"
DMG_PATH="/tmp/macfuse-${MACFUSE_VERSION}.dmg"

echo "[install] downloading macFUSE ${MACFUSE_VERSION} from ${DMG_URL}"
if ! curl -fL --retry 5 --retry-delay 5 --max-time 600 -o "$DMG_PATH" "$DMG_URL"; then
  echo "[install] FAILED — could not download $DMG_URL" >&2
  exit 1
fi
echo "[install] downloaded $(wc -c < "$DMG_PATH") bytes to $DMG_PATH"

echo "[install] mounting DMG"
MOUNT_POINT=$(hdiutil attach -nobrowse -readonly "$DMG_PATH" \
              | awk -F'\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -1)
if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
  echo "[install] FAILED — could not determine DMG mount point" >&2
  exit 1
fi
echo "[install] mounted at $MOUNT_POINT"
ls "$MOUNT_POINT" || true

# Locate the .pkg inside the DMG. macFUSE 4.x ships exactly one .pkg
# (Install macFUSE.pkg). Defensive: also probe for .app in case of future
# flips (per 12_macos_environments.md "Installation Patterns").
PKG_FILE=$(find "$MOUNT_POINT" -maxdepth 3 -name "*.pkg" -type f 2>/dev/null | head -1)
if [ -z "$PKG_FILE" ]; then
  echo "[install] FAILED — no .pkg found inside DMG" >&2
  ls -la "$MOUNT_POINT" >&2 || true
  hdiutil detach "$MOUNT_POINT" -force || true
  exit 1
fi
echo "[install] running installer: $PKG_FILE"
sudo installer -pkg "$PKG_FILE" -target /

hdiutil detach "$MOUNT_POINT" -force || true
rm -f "$DMG_PATH"

if [ ! -d "$BUNDLE_PATH" ]; then
  echo "[install] FAILED — $BUNDLE_PATH not present after install" >&2
  exit 1
fi

INSTALLED_VERSION=$(/usr/bin/defaults read "$BUNDLE_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
echo "[install] done — macFUSE $INSTALLED_VERSION at $BUNDLE_PATH"

# Surface a quick audit of what landed on disk so we can verify against
# verifier expectations.
echo "[install] post-install audit:"
ls -la "$BUNDLE_PATH/Contents/Resources/" 2>/dev/null | head -20 || true
ls /usr/local/lib/libfuse* 2>/dev/null || true
/usr/sbin/pkgutil --pkg-info io.macfuse.installer.components.core 2>/dev/null || true
