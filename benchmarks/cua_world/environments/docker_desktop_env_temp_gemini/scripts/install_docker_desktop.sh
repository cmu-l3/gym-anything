#!/bin/bash
# Docker Desktop Installation Script (pre_start hook)
# Installs Docker Desktop for Linux with all required dependencies
#
# Docker Desktop for Linux provides:
# - Graphical interface for managing containers and images
# - Docker Engine + Docker CLI
# - Docker Compose
# - Kubernetes integration
# - Docker Extensions marketplace
#
# Requirements:
# - 64-bit Ubuntu (22.04, 24.04 or later)
# - KVM virtualization support
# - 4 GB RAM minimum

set -e

echo "=== Installing Docker Desktop for Linux ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install prerequisites for Docker Desktop
echo "Installing prerequisites..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    gnome-terminal \
    pass \
    gpg

# Set up Docker's official GPG key and repository
echo "Setting up Docker repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository to apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update

# Install Docker Engine first (Docker Desktop will use this)
echo "Installing Docker Engine..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Download Docker Desktop .deb package
echo "Downloading Docker Desktop..."
DOCKER_DESKTOP_VERSION="4.36.0"
DOCKER_DESKTOP_DEB="/tmp/docker-desktop-amd64.deb"

# Try to download Docker Desktop
# Note: Docker Desktop requires accepting terms, so we download from official source
curl -fsSL -o "$DOCKER_DESKTOP_DEB" \
    "https://desktop.docker.com/linux/main/amd64/docker-desktop-${DOCKER_DESKTOP_VERSION}-amd64.deb" || \
curl -fsSL -o "$DOCKER_DESKTOP_DEB" \
    "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb" || \
wget -q -O "$DOCKER_DESKTOP_DEB" \
    "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"

# Install Docker Desktop
echo "Installing Docker Desktop..."
apt-get install -y "$DOCKER_DESKTOP_DEB"

# Clean up downloaded deb file
rm -f "$DOCKER_DESKTOP_DEB"

# Install additional tools for GUI automation
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install Python packages for verification
apt-get install -y python3-pip
pip3 install --no-cache-dir --break-system-packages Pillow requests || \
pip3 install --no-cache-dir Pillow requests || true

# Create docker group if it doesn't exist (Docker Desktop may need it)
getent group docker || groupadd docker

# Ensure ga user is in docker group
usermod -aG docker ga

# Set up pass for credential management (optional but recommended)
echo "Setting up credential management..."
su - ga -c "gpg --batch --passphrase '' --quick-gen-key 'GA User <ga@localhost>' default default never" 2>/dev/null || true
su - ga -c "pass init 'GA User <ga@localhost>'" 2>/dev/null || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker Engine version: $(docker --version 2>/dev/null || echo 'not available yet')"
echo "Docker Compose version: $(docker compose version 2>/dev/null || echo 'not available yet')"
echo "Docker Desktop: $(dpkg -l | grep docker-desktop | awk '{print $2, $3}' || echo 'installed')"
echo ""
echo "Docker Desktop will be configured and launched in post_start hook"
