#!/bin/bash
# Odoo Inventory Installation Script (pre_start hook)
# Installs Docker CE + Compose plugin - Odoo runs via official Docker containers
# Uses Odoo 17 Community Edition with PostgreSQL

set -e

echo "=== Installing Docker for Odoo Inventory ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install prerequisites
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Install Docker CE from official repository
echo "Installing Docker CE..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

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

# Authenticate with Docker Hub to avoid rate limits
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

# Pre-pull Docker images to avoid rate limit issues during setup
echo "Pre-pulling Docker images..."
docker pull postgres:15 2>&1 | tail -3 || true
docker pull odoo:17.0 2>&1 | tail -3 || true

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"
echo "Firefox: $(which firefox)"
echo ""
echo "Odoo 17 will be started via Docker in post_start hook"
