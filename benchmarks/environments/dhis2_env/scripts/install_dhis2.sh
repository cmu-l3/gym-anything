#!/bin/bash
# DHIS2 Installation Script (pre_start hook)
# Installs Docker, Firefox, and automation tools
set -e

echo "=== Installing DHIS2 Dependencies ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose
echo "Installing Docker and Docker Compose..."
apt-get install -y \
    docker.io \
    docker-compose \
    ca-certificates \
    gnupg \
    lsb-release

# Enable and start Docker
echo "Enabling Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Install Firefox (for web UI access)
echo "Installing Firefox..."
apt-get install -y firefox

# Install automation and utility tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    wget \
    jq \
    imagemagick \
    scrot \
    python3-pip

# Clean up apt cache to reduce image size
echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== DHIS2 Dependencies Installation Complete ==="
