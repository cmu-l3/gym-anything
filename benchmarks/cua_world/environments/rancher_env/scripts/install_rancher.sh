#!/bin/bash
# Rancher Installation Script (pre_start hook)
# Installs Docker and pulls the Rancher server image
set -e

echo "=== Installing Docker and Rancher dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and essential tools (no docker-compose needed, Rancher is a single container)
echo "Installing Docker..."
apt-get install -y \
    docker.io \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    jq

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Install Firefox browser
echo "Installing Firefox..."
apt-get install -y firefox

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install Python dependencies for verification
apt-get install -y python3-pip python3-requests
pip3 install --no-cache-dir requests || true

# Install openssl and certutil for certificate handling
apt-get install -y openssl libnss3-tools

# Pre-pull Rancher Docker image (saves time during setup)
echo "Pre-pulling Rancher Docker image..."
docker pull rancher/rancher:v2.8.5 || echo "WARNING: Failed to pre-pull Rancher image, will retry during setup"

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Firefox: $(which firefox)"
echo ""
echo "Rancher will be started via Docker in post_start hook"
