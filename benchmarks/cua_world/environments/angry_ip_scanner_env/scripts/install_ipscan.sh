#!/bin/bash
# set -euo pipefail

echo "=== Installing Angry IP Scanner and dependencies ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Java runtime (required by Angry IP Scanner)
echo "Installing OpenJDK 17..."
apt-get install -y \
    openjdk-17-jre \
    openjdk-17-jre-headless

# Install GUI automation and utility tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot

# Install network tools and services for scan targets
echo "Installing network services..."
apt-get install -y \
    openssh-server \
    apache2 \
    curl \
    wget \
    net-tools \
    iputils-ping \
    dnsutils \
    nmap

# Install Python libraries
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-dev

# Install file utilities
apt-get install -y \
    unzip \
    zip

# Download and install Angry IP Scanner
echo "Downloading Angry IP Scanner 3.9.3..."
wget -q https://github.com/angryip/ipscan/releases/download/3.9.3/ipscan_3.9.3_amd64.deb -O /tmp/ipscan.deb

echo "Installing Angry IP Scanner..."
dpkg -i /tmp/ipscan.deb || apt-get install -f -y
rm -f /tmp/ipscan.deb

# Verify installation
if command -v ipscan &>/dev/null; then
    echo "Angry IP Scanner installed successfully"
else
    echo "WARNING: ipscan command not found, checking alternative paths..."
    ls -la /usr/bin/ipscan* 2>/dev/null || true
    ls -la /usr/share/ipscan/ 2>/dev/null || true
    # Try to find it
    find / -name "ipscan" -type f 2>/dev/null | head -5
fi

# Enable SSH server for scan targets
systemctl enable ssh 2>/dev/null || true
systemctl start ssh 2>/dev/null || true

# Enable Apache for scan targets (provides an HTTP service to detect)
systemctl enable apache2 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Angry IP Scanner installation completed ==="
