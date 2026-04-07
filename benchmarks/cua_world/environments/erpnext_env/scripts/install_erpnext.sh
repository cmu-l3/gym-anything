#!/bin/bash
# ERPNext Installation Script (pre_start hook)
# Installs Docker and pulls ERPNext Docker images
# ERPNext runs via official frappe/erpnext Docker containers with MariaDB and Redis

echo "=== Installing Docker for ERPNext ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker engine
echo "Installing Docker..."
apt-get install -y docker.io

# Install docker-compose v1 (available in Ubuntu 22.04 repos)
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
    scrot

# Install Python tools for verification and setup
echo "Installing Python tools..."
apt-get install -y python3-pip python3-requests || true
pip3 install --no-cache-dir requests 2>/dev/null || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Pre-pull Docker images for ERPNext (speeds up post_start)
echo "Pre-pulling Docker images..."
docker pull frappe/erpnext:v15 || true
docker pull mariadb:10.6 || true
docker pull redis:6.2-alpine || true

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version 2>/dev/null || echo 'not installed')"
echo "Docker Compose version: $(docker-compose --version 2>/dev/null || echo 'not installed')"
echo "Firefox: $(which firefox 2>/dev/null || echo 'not installed')"
echo ""
echo "ERPNext containers will be started in the post_start hook"
