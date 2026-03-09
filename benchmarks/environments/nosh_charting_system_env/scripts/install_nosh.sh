#!/bin/bash
# NOSH ChartingSystem Installation Script (pre_start hook)
# Installs Docker - NOSH runs via official Docker container (shihjay2/nosh2)

set -e

echo "=== Installing Docker for NOSH ChartingSystem ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker
echo "Installing Docker..."
apt-get install -y docker.io

# Install Docker Compose v2 plugin directly from GitHub (more reliable than apt)
echo "Installing Docker Compose v2..."
mkdir -p /usr/local/lib/docker/cli-plugins
COMPOSE_VER="v2.24.5"
curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
# Symlink for ubuntu docker.io v28 compatibility
mkdir -p /usr/lib/docker/cli-plugins
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/lib/docker/cli-plugins/docker-compose

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group (allows running docker without sudo)
usermod -aG docker ga

# Verify docker compose works
docker compose version

# Install Firefox browser
echo "Installing Firefox..."
apt-get install -y firefox || snap install firefox || true

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    jq \
    python3-pip

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose: $(docker compose version)"
echo "Firefox: $(which firefox || echo 'snap')"
echo ""
echo "NOSH ChartingSystem will be started via Docker in post_start hook"
