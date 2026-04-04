#!/bin/bash
set -e

echo "=== Installing OpenToonz and dependencies ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install snapd for snap packages
echo "Installing snapd..."
apt-get install -y snapd

# Ensure snapd service is running
systemctl enable snapd.socket || true
systemctl start snapd.socket || true

# Wait for snapd to be ready
sleep 5

# Create symlink for classic snap support
ln -sf /var/lib/snapd/snap /snap || true

# Install OpenToonz via snap (most reliable method)
echo "Installing OpenToonz via snap..."
snap install opentoonz || {
    echo "Snap install failed, trying alternative method..."
    # Fallback: Install from deb-multimedia repository
    apt-get install -y wget gnupg

    # Add deb-multimedia repository
    wget -q http://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2016.8.1_all.deb -O /tmp/deb-multimedia-keyring.deb
    dpkg -i /tmp/deb-multimedia-keyring.deb || true

    echo "deb http://www.deb-multimedia.org stable main" >> /etc/apt/sources.list
    apt-get update
    apt-get install -y opentoonz opentoonz-data || true
}

# Install supporting tools
echo "Installing supporting tools..."
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    ffmpeg \
    python3-pip \
    python3-pil \
    wget \
    unzip \
    git

# Install Python packages for verification
pip3 install pillow numpy || true

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== OpenToonz installation complete ==="
