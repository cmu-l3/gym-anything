#!/bin/bash
# Jenkins Installation Script (pre_start hook)
# Installs Docker and Jenkins via official Docker image
# This approach is simpler and more reliable than manual installation

echo "=== Installing Docker and Jenkins ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose
echo "Installing Docker..."
apt-get install -y \
    docker.io \
    docker-compose \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

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
    jq \
    xmlstarlet \
    imagemagick

# Install Git (for sample repositories)
echo "Installing Git..."
apt-get install -y git

# Install Java (required for Jenkins CLI operations)
echo "Installing Java..."
apt-get install -y openjdk-21-jdk-headless

# Install Python XML parsing for verification scripts
apt-get install -y python3-pip python3-lxml
pip3 install --no-cache-dir lxml requests || true

# Pre-pull Jenkins Docker image (saves time on first boot)
echo "Pre-pulling Jenkins Docker image..."
docker pull jenkins/jenkins:lts-jdk21 || echo "WARNING: Failed to pre-pull Jenkins image"

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Firefox: $(which firefox)"
echo "Java version: $(java -version 2>&1 | head -1)"
echo "Git version: $(git --version)"
echo ""
echo "Jenkins will be started via Docker in post_start hook"
