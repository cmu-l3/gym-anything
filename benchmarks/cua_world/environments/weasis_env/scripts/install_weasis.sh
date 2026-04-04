#!/bin/bash
# set -euo pipefail

echo "=== Installing Weasis DICOM Viewer and related packages ==="

# Update package manager
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Install snapd for snap package installation
echo "Installing snapd..."
apt-get install -y snapd

# Ensure snapd socket is available
systemctl enable snapd.socket || true
systemctl start snapd.socket || true

# Wait for snapd to be ready
sleep 5

# Install Weasis via snap
echo "Installing Weasis via snap..."
snap install weasis || {
    echo "Snap installation failed, trying alternative method..."
    # Alternative: Download native installer
    WEASIS_VERSION="4.5.1"
    wget -q "https://github.com/nroduit/Weasis/releases/download/v${WEASIS_VERSION}/weasis_${WEASIS_VERSION}-1_amd64.deb" -O /tmp/weasis.deb
    dpkg -i /tmp/weasis.deb || apt-get install -f -y
    rm -f /tmp/weasis.deb
}

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
    pydicom \
    numpy \
    opencv-python-headless

# Install network tools
echo "Installing network tools..."
apt-get install -y \
    curl \
    wget \
    unzip

# Install DICOM tools
echo "Installing DICOM tools..."
apt-get install -y \
    dcmtk || echo "dcmtk not available, skipping"

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Weasis DICOM Viewer installation completed ==="
