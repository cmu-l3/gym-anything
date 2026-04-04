#!/bin/bash
# set -euo pipefail

echo "=== Installing WPS Office Spreadsheet and related packages ==="

# Update package manager
apt-get update

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Install prerequisites and dependencies
echo "Installing dependencies..."
apt-get install -y \
    wget \
    curl \
    gdebi-core \
    libglu1-mesa \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-render-util0 \
    libxcb-xinerama0 \
    libxcb-xkb1 \
    libxkbcommon-x11-0 \
    libegl1 \
    libopengl0 \
    libxslt1.1 \
    qt5-gtk-platformtheme

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot

# Install Python dependencies for spreadsheet verification
echo "Installing Python dependencies..."
apt-get install -y \
    python3-pip \
    python3-dev \
    python3-lxml

pip3 install --no-cache-dir --break-system-packages \
    openpyxl \
    xlrd \
    pandas \
    lxml 2>/dev/null || \
pip3 install --no-cache-dir \
    openpyxl \
    xlrd \
    pandas \
    lxml || true

# Install file handling utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    p7zip-full

# Install fonts for better rendering and MS Office compatibility
echo "Installing additional fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-liberation2 \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-crosextra-carlito \
    fonts-crosextra-caladea \
    fonts-opensymbol \
    ttf-mscorefonts-installer || apt-get install -y --fix-broken

# Download WPS Office (includes spreadsheet - et)
echo "Downloading WPS Office..."
WPS_DEB="/tmp/wps-office.deb"
WPS_URL="https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/11723/wps-office_11.1.0.11723.XA_amd64.deb"

# Try multiple download attempts with different methods
if ! wget -q --show-progress -O "$WPS_DEB" "$WPS_URL" 2>/dev/null; then
    echo "wget failed, trying curl..."
    if ! curl -L -o "$WPS_DEB" "$WPS_URL" 2>/dev/null; then
        echo "ERROR: Failed to download WPS Office"
        exit 1
    fi
fi

# Verify download
if [ ! -f "$WPS_DEB" ] || [ $(stat -c%s "$WPS_DEB") -lt 100000000 ]; then
    echo "ERROR: Downloaded file is invalid or too small"
    exit 1
fi

echo "Download complete. Size: $(stat -c%s "$WPS_DEB") bytes"

# Install WPS Office
echo "Installing WPS Office..."
gdebi -n "$WPS_DEB" || dpkg -i "$WPS_DEB"

# Fix any dependency issues
apt-get install -f -y

# Clean up downloaded file
rm -f "$WPS_DEB"

# Verify installation
if command -v et &>/dev/null || [ -f /usr/bin/et ]; then
    echo "WPS Office Spreadsheet installed successfully"
    et --version 2>/dev/null || true
else
    echo "WARNING: WPS Office Spreadsheet binary not found, checking alternatives..."
    ls -la /opt/kingsoft/ 2>/dev/null || true
    ls -la /usr/share/applications/wps* 2>/dev/null || true
fi

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== WPS Office Spreadsheet installation completed ==="
