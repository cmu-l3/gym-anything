#!/bin/bash
set -euo pipefail

echo "=== Installing draw.io Desktop (.deb package) ==="

export DEBIAN_FRONTEND=noninteractive

# Update package manager
echo "Updating package lists..."
apt-get update

# Install dependencies for Electron-based draw.io .deb
echo "Installing system dependencies..."
apt-get install -y \
    libnss3 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libgbm1 \
    libasound2 \
    libdrm2 \
    libxshmfence1 \
    libx11-xcb1 \
    libxrandr2 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libpango-1.0-0 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgcc-s1 \
    libglib2.0-0 \
    libnspr4 \
    libpangocairo-1.0-0 \
    libstdc++6 \
    libxcb1 \
    libxext6 \
    libxtst6 \
    wget \
    curl

# Install GUI automation and utility tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    imagemagick \
    jq

# Install Python libraries for verification
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-dev \
    python3-lxml

pip3 install --no-cache-dir \
    pillow \
    xmltodict

# Download draw.io Desktop .deb package
echo "Downloading draw.io Desktop .deb package..."
DRAWIO_VERSION="26.0.9"
DRAWIO_DEB="drawio-amd64-${DRAWIO_VERSION}.deb"
DRAWIO_URL="https://github.com/jgraph/drawio-desktop/releases/download/v${DRAWIO_VERSION}/${DRAWIO_DEB}"

cd /tmp

wget -q --show-progress -O "$DRAWIO_DEB" "$DRAWIO_URL" || {
    echo "Warning: Could not download version ${DRAWIO_VERSION}, trying latest release..."
    LATEST_URL=$(curl -sL https://api.github.com/repos/jgraph/drawio-desktop/releases/latest | \
        jq -r '.assets[] | select(.name | test("amd64.*\\.deb$")) | .browser_download_url' | head -1)
    if [ -n "$LATEST_URL" ]; then
        wget -q --show-progress -O "$DRAWIO_DEB" "$LATEST_URL"
    else
        echo "ERROR: Could not download draw.io .deb package"
        exit 1
    fi
}

# Install the .deb package
echo "Installing draw.io .deb package..."
dpkg -i "$DRAWIO_DEB" || apt-get install -f -y
rm -f "$DRAWIO_DEB"

# Verify installation
echo "Verifying draw.io installation..."
if command -v drawio &>/dev/null; then
    echo "draw.io installed successfully: $(which drawio)"
elif [ -f /opt/drawio/drawio ]; then
    echo "draw.io binary found at /opt/drawio/drawio"
    ln -sf /opt/drawio/drawio /usr/local/bin/drawio
else
    echo "ERROR: draw.io installation failed"
    exit 1
fi

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== draw.io Desktop installation completed ==="
