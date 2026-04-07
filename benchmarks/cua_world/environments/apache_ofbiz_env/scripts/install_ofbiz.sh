#!/bin/bash
# Apache OFBiz Installation Script (pre_start hook)
# Installs Docker and pulls the official OFBiz Docker image with demo data.
# OFBiz runs via the official ghcr.io/apache/ofbiz image with embedded Derby DB.

set -e

echo "=== Installing Docker for Apache OFBiz ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker engine
echo "Installing Docker..."
apt-get install -y docker.io

# Install docker-compose (v1 from Ubuntu repos)
echo "Installing docker-compose..."
apt-get install -y docker-compose || true

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
echo "Waiting for Docker daemon..."
for i in $(seq 1 30); do
    if docker info > /dev/null 2>&1; then
        echo "Docker is ready"
        break
    fi
    sleep 2
done

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
    curl \
    jq \
    scrot \
    libnss3-tools

# Install Python tools for task setup scripts
echo "Installing Python tools..."
apt-get install -y python3-pip python3-requests || true
pip3 install --no-cache-dir requests 2>/dev/null || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Pre-pull the official OFBiz Docker image (speeds up post_start)
echo "Pre-pulling official OFBiz Docker image..."
docker pull ghcr.io/apache/ofbiz:release24.09-plugins-snapshot || \
    docker pull ghcr.io/apache/ofbiz:trunk-plugins-snapshot || \
    echo "WARNING: Could not pre-pull OFBiz image, will retry in setup"

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version 2>/dev/null || echo 'not installed')"
echo "Docker Compose version: $(docker-compose --version 2>/dev/null || echo 'not installed')"
echo "Firefox: $(which firefox 2>/dev/null || echo 'not installed')"
echo ""
echo "OFBiz container will be started in the post_start hook"
