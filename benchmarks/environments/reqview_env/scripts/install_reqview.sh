#!/bin/bash
set -euo pipefail

echo "=== Installing ReqView Requirements Management Tool ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update -y

# Install Electron/GTK dependencies required by ReqView
echo "Installing dependencies..."
apt-get install -y \
    curl \
    wget \
    libgbm1 \
    libgtk-3-0 \
    libnss3 \
    libxss1 \
    libatk-bridge2.0-0 \
    libatspi2.0-0 \
    libgconf-2-4 \
    libxcb-dri3-0 \
    libdrm2 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libasound2 \
    libpangocairo-1.0-0 \
    libx11-xcb1 \
    libxcb1 \
    fonts-liberation \
    xdg-utils \
    scrot \
    wmctrl \
    xdotool \
    python3-pip

# Download ReqView deb package from official S3 distribution
# Using curl -L to follow any redirects (wget fails with 403 on this bucket)
REQVIEW_VERSION="2.21.2"
REQVIEW_DEB="/tmp/ReqView-${REQVIEW_VERSION}-linux-amd64.deb"

echo "Downloading ReqView ${REQVIEW_VERSION}..."

DOWNLOAD_SUCCESS=false
# Try latest version first, then fall back to older versions
for VERSION in "2.21.2" "2.21.0" "2.20.1" "2.19.0"; do
    URL="https://s3.eu-central-1.amazonaws.com/reqview-desktop-linux/ReqView-${VERSION}-linux-amd64.deb"
    echo "Trying: ${URL}"
    if curl -sL --max-time 300 --retry 2 -o "${REQVIEW_DEB}" "${URL}" && \
       file "${REQVIEW_DEB}" | grep -q "Debian"; then
        echo "Downloaded ReqView ${VERSION} successfully"
        DOWNLOAD_SUCCESS=true
        break
    fi
    echo "Failed for version ${VERSION}, trying next..."
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "ERROR: Could not download ReqView package from any version"
    exit 1
fi

echo "Installing ReqView package..."
dpkg -i "${REQVIEW_DEB}" || apt-get install -f -y

# Verify installation
REQVIEW_BIN=""
for candidate in /usr/bin/reqview /usr/local/bin/reqview /opt/ReqView/reqview; do
    if [ -f "$candidate" ]; then
        REQVIEW_BIN="$candidate"
        break
    fi
done

if [ -z "$REQVIEW_BIN" ]; then
    REQVIEW_BIN=$(find /usr /opt -name "reqview" -type f 2>/dev/null | grep -v ".dep" | head -1 || true)
fi

if [ -n "$REQVIEW_BIN" ]; then
    echo "ReqView installed at: $REQVIEW_BIN"
    # Ensure it's in PATH
    if [ "$REQVIEW_BIN" != "/usr/bin/reqview" ] && [ ! -f /usr/bin/reqview ]; then
        ln -sf "$REQVIEW_BIN" /usr/local/bin/reqview
    fi
else
    echo "WARNING: reqview binary not found at expected locations"
fi

# Cleanup
rm -f "${REQVIEW_DEB}"

echo "=== ReqView installation complete ==="
