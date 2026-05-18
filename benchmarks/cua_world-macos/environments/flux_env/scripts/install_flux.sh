#!/bin/bash
# pre_start: download Flux.zip from justgetflux.com, extract to /Applications/Flux.app,
# strip quarantine. The Flux bundle is a universal binary (x86_64 + arm64), so no
# Rosetta is required on the Apple-Silicon use.computer fleet.
#
# Download is a 302 from justgetflux.com/mac/Flux.zip to a BunnyCDN-backed URL.
# Idempotent: if /Applications/Flux.app is already present, just print the
# version and exit 0.
set -eu

APP="/Applications/Flux.app"

if [ -d "$APP" ]; then
    VERSION=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    echo "[install] f.lux already present at $APP (version $VERSION); skipping download"
    echo "[install] done"
    exit 0
fi

ZIP_URL="https://justgetflux.com/mac/Flux.zip"
ZIP_PATH="/tmp/Flux.zip"

echo "[install] downloading $ZIP_URL"
/usr/bin/curl -fL --retry 5 --retry-delay 5 -o "$ZIP_PATH" "$ZIP_URL"
SIZE=$(/usr/bin/stat -f %z "$ZIP_PATH" 2>/dev/null || echo 0)
echo "[install] downloaded $SIZE bytes"

# Sanity check: the zip should be ~2 MB. Anything materially smaller means the
# CDN served an error page or the URL moved. Hard-fail so the env doesn't
# silently produce a broken sandbox.
if [ "$SIZE" -lt 1000000 ]; then
    echo "[install] FAILED — downloaded zip is too small ($SIZE bytes); CDN likely served an error." >&2
    /usr/bin/head -c 400 "$ZIP_PATH" >&2 || true
    exit 1
fi

WORK=$(/usr/bin/mktemp -d /tmp/flux_install.XXXXXX)
echo "[install] extracting to $WORK"
/usr/bin/unzip -qo "$ZIP_PATH" -d "$WORK"

APP_SRC="$WORK/Flux.app"
if [ ! -d "$APP_SRC" ]; then
    echo "[install] FAILED — Flux.app not present in extracted zip:" >&2
    /bin/ls -la "$WORK" >&2
    exit 1
fi

sudo /usr/bin/ditto "$APP_SRC" "$APP"
# Strip Gatekeeper quarantine xattr (safe no-op if absent).
sudo /usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

rm -rf "$WORK" "$ZIP_PATH"

VERSION=$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
ARCHS=$(/usr/bin/lipo -archs "$APP/Contents/MacOS/Flux" 2>/dev/null || echo "?")
echo "[install] f.lux $VERSION installed at $APP (archs: $ARCHS)"
echo "[install] done"
