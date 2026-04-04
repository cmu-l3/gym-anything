#!/bin/bash
# NextGen Connect Integration Engine Installation Script (pre_start hook)
# Installs Docker, Firefox, and pulls the official NextGen Connect image

set -e

echo "=== Installing NextGen Connect Integration Engine ==="

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

# Add ga user to docker group
usermod -aG docker ga

# Install Java runtime (needed by some NextGen Connect operations)
echo "Installing Java runtime..."
apt-get install -y default-jre

# Install Firefox browser (for accessing the web console/landing page)
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
    imagemagick \
    netcat-openbsd

# Install Python dependencies for verification scripts
echo "Installing Python dependencies..."
apt-get install -y python3-pip
pip3 install --no-cache-dir lxml requests beautifulsoup4 || true

# Pull NextGen Connect Docker image
# Using version 4.5.0 as it's the last fully open-source version before licensing changes
echo "Pulling NextGen Connect Docker image..."
docker pull nextgenhealthcare/connect:4.5.0

# Pull PostgreSQL for message storage
echo "Pulling PostgreSQL Docker image..."
docker pull postgres:15

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Java: $(java -version 2>&1 | head -1)"
echo "Firefox: $(which firefox)"
echo "NextGen Connect image pulled: $(docker images | grep nextgenhealthcare/connect)"
echo ""
echo "NextGen Connect will be started via Docker in post_start hook"
