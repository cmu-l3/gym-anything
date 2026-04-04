#!/bin/bash
set -euo pipefail

echo "=== Installing Google Earth Pro ==="

# Configure faster APT mirrors
sudo cat > /etc/apt/apt.conf.d/99custom << 'APT_CONF_EOF'
Acquire::Retries "3";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
APT_CONF_EOF

# Install dependencies
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    wget \
    lsb-release \
    libglu1-mesa \
    libsm6 \
    libfontconfig1 \
    libxi6 \
    libxrender1 \
    libxrandr2 \
    libxfixes3 \
    libxcursor1 \
    libxinerama1 \
    libfreetype6 \
    xdg-utils

# Download Google Earth Pro (free since 2015)
echo "Downloading Google Earth Pro..."
wget -q -O /tmp/google-earth-pro-stable_current_amd64.deb \
    "https://dl.google.com/dl/earth/client/current/google-earth-pro-stable_current_amd64.deb"

# Install Google Earth Pro
echo "Installing Google Earth Pro..."
sudo dpkg -i /tmp/google-earth-pro-stable_current_amd64.deb || sudo apt-get install -f -y

# Install verification tools
echo "Installing verification tools..."
sudo apt-get install -y \
    python3-pil \
    python3-numpy \
    imagemagick \
    scrot \
    wmctrl \
    xdotool

# Cleanup
rm -f /tmp/google-earth-pro-stable_current_amd64.deb

echo "=== Google Earth Pro installation completed ==="
