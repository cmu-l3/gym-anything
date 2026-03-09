#!/bin/bash
set -e

echo "=== Installing Wondershare EdrawMax ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update -qq

# Install system dependencies required by EdrawMax (Qt5-based app) and UI automation tools
apt-get install -y --no-install-recommends \
    wget \
    curl \
    xdotool \
    wmctrl \
    imagemagick \
    libgtk-3-0 \
    libglib2.0-0 \
    libnss3 \
    libasound2 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libxkbcommon0 \
    libpangocairo-1.0-0 \
    libatk1.0-0 \
    libcairo2 \
    libgdk-pixbuf2.0-0 \
    libsecret-1-0 \
    libdbus-1-3 \
    libgl1 \
    libglu1-mesa \
    xvfb \
    python3-pip

echo "=== Dependencies installed ==="

# Download EdrawMax .deb package
EDRAWMAX_VERSION="15.0.6"
EDRAWMAX_DEB="edrawmax_${EDRAWMAX_VERSION}_en.deb"
DL_DIR="/tmp/edrawmax_install"
mkdir -p "$DL_DIR"

PRIMARY_URL="https://download.wondershare.com/business/prd/${EDRAWMAX_DEB}"
FALLBACK_URL="https://download.edrawsoft.com/${EDRAWMAX_DEB}"

echo "Downloading EdrawMax ${EDRAWMAX_VERSION} (~518MB)..."

download_ok=false
for URL in "$PRIMARY_URL" "$FALLBACK_URL"; do
    echo "Trying: $URL"
    if wget -q --show-progress --timeout=300 --tries=3 \
            -O "$DL_DIR/${EDRAWMAX_DEB}" "$URL" 2>&1; then
        DEB_SIZE=$(stat -c%s "$DL_DIR/${EDRAWMAX_DEB}" 2>/dev/null || echo 0)
        echo "Downloaded: ${DEB_SIZE} bytes"
        if [ "$DEB_SIZE" -gt 100000000 ]; then
            download_ok=true
            break
        else
            echo "File too small (${DEB_SIZE} bytes), trying next URL..."
            rm -f "$DL_DIR/${EDRAWMAX_DEB}"
        fi
    else
        echo "Download failed from $URL, trying next..."
        rm -f "$DL_DIR/${EDRAWMAX_DEB}"
    fi
done

if [ "$download_ok" = "false" ]; then
    echo "ERROR: All download attempts failed for EdrawMax ${EDRAWMAX_VERSION}"
    echo "Please check the download URL or network connectivity."
    exit 1
fi

echo "=== Installing EdrawMax package ==="

# Install with dpkg (may fail on missing deps, fixed below)
dpkg -i "$DL_DIR/${EDRAWMAX_DEB}" 2>&1 || true

# Fix any missing dependencies
apt-get install -f -y 2>&1

# Verify EdrawMax installation
EDRAWMAX_BIN=""
for candidate in "/usr/bin/edrawmax" "/usr/local/bin/edrawmax"; do
    if [ -x "$candidate" ]; then
        EDRAWMAX_BIN="$candidate"
        break
    fi
done

if [ -z "$EDRAWMAX_BIN" ]; then
    # Search in /opt
    EDRAWMAX_BIN=$(find /opt -name "EdrawMax" -executable -type f 2>/dev/null | head -1)
fi

if [ -n "$EDRAWMAX_BIN" ]; then
    echo "EdrawMax installed at: $EDRAWMAX_BIN"
else
    echo "WARNING: EdrawMax binary not found in expected locations. Listing /opt:"
    ls -la /opt/ 2>/dev/null || true
    find /opt -maxdepth 3 -name "*draw*" -o -name "*Draw*" 2>/dev/null || true
fi

# Create a symlink if only found in /opt
if [ -z "$(which edrawmax 2>/dev/null)" ] && [ -n "$EDRAWMAX_BIN" ]; then
    ln -sf "$EDRAWMAX_BIN" /usr/local/bin/edrawmax
    echo "Created symlink: /usr/local/bin/edrawmax -> $EDRAWMAX_BIN"
fi

# Clean up installer
rm -rf "$DL_DIR"

echo "=== EdrawMax installation complete ==="
