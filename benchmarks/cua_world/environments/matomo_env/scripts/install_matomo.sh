#!/bin/bash
# Matomo Installation Script (pre_start hook)
# Installs Docker - Matomo runs via official Docker container

set -e

echo "=== Installing Docker for Matomo ==="

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

# Install Python MySQL connector for verification scripts
apt-get install -y python3-pip python3-pymysql
pip3 install --no-cache-dir mysql-connector-python PyMySQL || true

# Authenticate with Docker Hub to avoid rate limits
echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin \
    && echo "Docker Hub auth successful" \
    || echo "Docker Hub auth failed (continuing anyway)"

# Pre-pull Docker images during install phase
if [ -f /workspace/config/docker-compose.yml ]; then
    mkdir -p /home/ga/matomo
    cp /workspace/config/docker-compose.yml /home/ga/matomo/
    chown -R ga:ga /home/ga/matomo
    cd /home/ga/matomo
    docker-compose pull || echo "Warning: docker-compose pull failed (will retry in setup)"
fi

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
echo "Matomo will be started via Docker in post_start hook"
