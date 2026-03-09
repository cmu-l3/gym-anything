#!/bin/bash
set -e

echo "=== Installing Nx Witness VMS ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install dependencies required by Nx Witness server
apt-get install -y \
    make \
    net-tools \
    ffmpeg \
    cifs-utils \
    curl \
    wget \
    jq \
    python3-pip \
    scrot \
    imagemagick \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    gdebi-core

# Install Firefox (for web admin interface)
apt-get install -y firefox

# Install GUI utilities
apt-get install -y \
    xvfb \
    x11vnc \
    xterm

# Download Nx Witness Media Server deb package
# Using version 5.1.5 (stable, widely supported on Ubuntu 20.04/22.04)
NX_VERSION="5.1.5.39242"
NX_DEB="nxwitness-server-${NX_VERSION}-linux_x64.deb"
NX_URL="https://updates.networkoptix.com/default/${NX_VERSION}/linux/${NX_DEB}"

echo "=== Downloading Nx Witness Server ${NX_VERSION} ==="
cd /tmp
wget -q --timeout=300 "${NX_URL}" -O "${NX_DEB}" || {
    echo "Primary URL failed, trying alternative..."
    # Try 6.0.x as fallback
    NX_VERSION="6.0.1.39873"
    NX_DEB="nxwitness-server-${NX_VERSION}-linux_x64.deb"
    NX_URL="https://updates.networkoptix.com/default/${NX_VERSION}/linux/${NX_DEB}"
    wget -q --timeout=300 "${NX_URL}" -O "${NX_DEB}"
}

echo "=== Installing Nx Witness Server ==="
# Install the deb package
dpkg -i "/tmp/${NX_DEB}" || apt-get install -f -y

# Verify installation
if systemctl list-unit-files | grep -q networkoptix-mediaserver; then
    echo "Nx Witness Media Server service registered successfully"
else
    echo "ERROR: Nx Witness service not found after installation"
    exit 1
fi

# Download and install Nx Witness Desktop Client
NX_CLIENT_DEB="nxwitness-client-${NX_VERSION}-linux_x64.deb"
NX_CLIENT_URL="https://updates.networkoptix.com/default/${NX_VERSION}/linux/${NX_CLIENT_DEB}"

echo "=== Downloading Nx Witness Desktop Client ==="
wget -q --timeout=300 "${NX_CLIENT_URL}" -O "/tmp/${NX_CLIENT_DEB}" || {
    echo "Warning: Client download failed, skipping client installation"
}

if [ -f "/tmp/${NX_CLIENT_DEB}" ]; then
    echo "=== Installing Nx Witness Desktop Client ==="
    dpkg -i "/tmp/${NX_CLIENT_DEB}" || apt-get install -f -y
    echo "Desktop client installed"
fi

# Install Python packages for API interaction
pip3 install requests urllib3 2>/dev/null || true

# Clean up downloaded files
rm -f /tmp/*.deb

echo "=== Nx Witness VMS installation complete ==="
