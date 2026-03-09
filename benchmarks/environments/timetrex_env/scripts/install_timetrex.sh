#!/bin/bash
# TimeTrex Installation Script (pre_start hook)
# Installs Docker - TimeTrex runs via Docker container
# This is more reliable than manual LAMP setup

set -e

echo "=== Installing Docker for TimeTrex ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose
echo "Installing Docker..."
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
    jq

# Install Python PostgreSQL connector for verification scripts
apt-get install -y python3-pip python3-psycopg2
pip3 install --no-cache-dir psycopg2-binary || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Firefox: $(which firefox)"
echo ""
echo "TimeTrex will be started via Docker in post_start hook"
