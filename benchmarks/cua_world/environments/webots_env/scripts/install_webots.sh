#!/bin/bash
set -euo pipefail

echo "=== Installing Webots Robot Simulator ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install OpenGL/Mesa dependencies for software rendering (no GPU in VM)
echo "Installing OpenGL and Mesa dependencies..."
apt-get install -y \
    libgl1-mesa-dri \
    libglu1-mesa \
    libegl1-mesa \
    mesa-utils \
    libxkbcommon-x11-0 \
    libxcb-xinerama0 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-render-util0

# Install GUI automation tools
echo "Installing GUI automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    scrot \
    x11-utils

# Install general utilities
apt-get install -y \
    wget \
    curl \
    python3-pip \
    python3-dev \
    ffmpeg

# Download Webots R2023b .deb package (stable, tested on Ubuntu 22.04)
echo "Downloading Webots R2023b..."
WEBOTS_DEB="/tmp/webots.deb"
WEBOTS_URL_PRIMARY="https://github.com/cyberbotics/webots/releases/download/R2023b/webots_2023b_amd64.deb"
WEBOTS_URL_FALLBACK="https://github.com/cyberbotics/webots/releases/download/R2025a/webots_2025a_amd64.deb"

if ! wget -q --show-progress -O "$WEBOTS_DEB" "$WEBOTS_URL_PRIMARY"; then
    echo "Primary download failed, trying fallback URL..."
    wget -q --show-progress -O "$WEBOTS_DEB" "$WEBOTS_URL_FALLBACK"
fi

# Install Webots and resolve dependencies
echo "Installing Webots .deb package..."
dpkg -i "$WEBOTS_DEB" || true
apt-get install -f -y

# Verify installation
if [ -x /usr/local/webots/webots ]; then
    echo "Webots installed successfully at /usr/local/webots/"
else
    echo "ERROR: Webots binary not found after installation"
    exit 1
fi

# Create symlink for easy access
ln -sf /usr/local/webots/webots /usr/local/bin/webots 2>/dev/null || true

# Clean up
rm -f "$WEBOTS_DEB"
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Webots installation complete ==="
