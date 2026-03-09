#!/bin/bash
# OpenMRS O3 Installation Script (pre_start hook)
# Installs Docker and supporting tools.
# OpenMRS O3 Reference Application runs via official Docker images.

set -e

echo "=== Installing prerequisites for OpenMRS O3 ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose v2
echo "Installing Docker..."
apt-get install -y docker.io docker-compose-v2

# Start and enable Docker
systemctl enable docker
systemctl start docker

# Add ga to docker group
usermod -aG docker ga

# Install Firefox (for browser-based interaction)
echo "Installing Firefox..."
apt-get install -y firefox

# Install GUI automation and screenshot tools
echo "Installing GUI automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    imagemagick \
    curl \
    jq \
    python3-pip \
    python3-pymysql

# Install Python packages for verification
pip3 install --no-cache-dir requests PyMySQL 2>/dev/null || true

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation complete ==="
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker compose version)"
echo "Firefox: $(which firefox)"
echo "OpenMRS O3 will be started in post_start via Docker Compose"
