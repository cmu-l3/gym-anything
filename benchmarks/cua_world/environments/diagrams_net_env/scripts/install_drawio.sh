#!/bin/bash
set -euo pipefail

echo "=== Installing Diagrams.net (draw.io) Desktop and related packages ==="

# Update package manager
echo "Updating package lists..."
apt-get update

# Install dependencies for AppImage
echo "Installing dependencies for AppImage..."
apt-get install -y \
    libfuse2 \
    libnss3 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libgbm1 \
    libasound2

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install Python libraries for verification
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-dev

pip3 install --no-cache-dir \
    pillow \
    lxml \
    xmltodict

# Install file utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    curl \
    wget \
    jq

# Download diagrams.net (draw.io) desktop AppImage
echo "Downloading diagrams.net desktop AppImage..."
DRAWIO_VERSION="26.0.9"
DRAWIO_APPIMAGE="drawio-x86_64-${DRAWIO_VERSION}.AppImage"
DRAWIO_URL="https://github.com/jgraph/drawio-desktop/releases/download/v${DRAWIO_VERSION}/${DRAWIO_APPIMAGE}"

# Download to /opt
mkdir -p /opt/drawio
cd /opt/drawio

# Download AppImage
wget -q --show-progress -O drawio.AppImage "$DRAWIO_URL" || {
    echo "Warning: Could not download version ${DRAWIO_VERSION}, trying latest release..."
    # Fallback: get latest release URL
    LATEST_URL=$(curl -sL https://api.github.com/repos/jgraph/drawio-desktop/releases/latest | jq -r '.assets[] | select(.name | test("x86_64.*AppImage$")) | .browser_download_url' | head -1)
    if [ -n "$LATEST_URL" ]; then
        wget -q --show-progress -O drawio.AppImage "$LATEST_URL"
    else
        echo "ERROR: Could not download draw.io AppImage"
        exit 1
    fi
}

# Make AppImage executable
chmod +x drawio.AppImage

# Create symlink for easy access
ln -sf /opt/drawio/drawio.AppImage /usr/local/bin/drawio

# Verify installation
echo "Verifying draw.io installation..."
if [ -f /opt/drawio/drawio.AppImage ]; then
    echo "draw.io AppImage installed successfully at /opt/drawio/drawio.AppImage"
    ls -la /opt/drawio/
else
    echo "ERROR: draw.io installation failed"
    exit 1
fi

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Diagrams.net (draw.io) Desktop installation completed ==="
