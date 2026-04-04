#!/bin/bash
# OSCAR EMR Installation Script (pre_start hook)
# Installs Docker - OSCAR EMR runs via Docker containers (open-osp stack)
# Architecture: MariaDB + Tomcat/Java OSCAR WAR via openosp/open-osp image

set -e

echo "=== Installing Docker for OSCAR EMR ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose
echo "Installing Docker..."
# docker.io on Ubuntu 22.04 includes docker compose v2 as a plugin ('docker compose')
# Also install docker-compose v1 for compatibility
apt-get install -y docker.io docker-compose

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group (allows running docker without sudo)
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
    wget \
    imagemagick \
    scrot

# Install Python and MySQL connector for verification
apt-get install -y python3-pip python3-pymysql
pip3 install --no-cache-dir PyMySQL mysql-connector-python 2>/dev/null || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
echo "Firefox: $(which firefox)"
echo ""
echo "OSCAR EMR will be started via Docker in post_start hook"
