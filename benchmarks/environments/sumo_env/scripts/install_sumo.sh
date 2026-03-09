#!/bin/bash
set -e

echo "=== Installing SUMO (Simulation of Urban Mobility) ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install prerequisites for adding PPA
echo "Installing prerequisites..."
apt-get install -y \
    software-properties-common \
    gnupg \
    wget \
    curl \
    ca-certificates

# Add SUMO PPA repository
echo "Adding SUMO stable PPA..."
add-apt-repository -y ppa:sumo/stable
apt-get update

# Install SUMO packages
echo "Installing SUMO..."
apt-get install -y \
    sumo \
    sumo-tools \
    sumo-doc

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install Python libraries
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-dev

# Set SUMO_HOME system-wide
echo 'export SUMO_HOME="/usr/share/sumo"' >> /etc/profile.d/sumo.sh
chmod +x /etc/profile.d/sumo.sh

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== SUMO installation complete ==="

# Verify installation
if command -v sumo &> /dev/null; then
    echo "SUMO version: $(sumo --version 2>&1 | head -1)"
else
    echo "Warning: sumo command not found in PATH"
fi

if command -v sumo-gui &> /dev/null; then
    echo "sumo-gui available"
else
    echo "Warning: sumo-gui not found"
fi

if command -v netedit &> /dev/null; then
    echo "netedit available"
else
    echo "Warning: netedit not found"
fi

echo "SUMO_HOME=/usr/share/sumo"
ls /usr/share/sumo/ 2>/dev/null || echo "SUMO_HOME directory not found"
