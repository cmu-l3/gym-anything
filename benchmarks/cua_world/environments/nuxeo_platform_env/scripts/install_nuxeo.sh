#!/bin/bash
# Nuxeo Platform Installation Script (pre_start hook)
# Installs Docker, Docker Compose, Firefox, and GUI automation tools.
# Nuxeo itself runs as a Docker container started in the post_start hook.

set -e

echo "=== Installing prerequisites for Nuxeo Platform ==="

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update

echo "Installing Docker..."
apt-get install -y docker.io

# Install Docker Compose v1 (use 'docker-compose' command; 'docker compose' v2 is not available on this image)
apt-get install -y docker-compose

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

echo "Installing Firefox browser..."
apt-get install -y firefox

echo "Installing GUI automation and utility tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    jq \
    python3-pip \
    python3-requests \
    scrot \
    imagemagick \
    wget \
    unzip

# Install Python requests library for verification scripts
pip3 install --no-cache-dir requests 2>/dev/null || true

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version 2>/dev/null || echo 'not available yet')"
echo "Firefox: $(which firefox)"
echo ""
echo "Nuxeo will be started via Docker Compose in the post_start hook."
