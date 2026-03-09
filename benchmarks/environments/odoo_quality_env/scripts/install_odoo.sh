#!/bin/bash
set -e

echo "=== Installing Odoo Quality Environment Prerequisites ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install prerequisites
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    python3-pip \
    scrot \
    imagemagick \
    x11-utils \
    wmctrl \
    xdotool \
    wget \
    software-properties-common

# Note: Firefox (snap version) is pre-installed in the base image.
# Task hooks use ensure_firefox() which handles snap lock artifacts.

# Install Docker CE from official repository (docker-compose-plugin requires Docker CE)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Enable and start Docker daemon
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Create Odoo working directory
mkdir -p /opt/odoo

# Copy config files to writable location (workspace mounts are read-only)
cp /workspace/config/docker-compose.yml /opt/odoo/
cp /workspace/config/odoo.conf /opt/odoo/

# Set ownership
chown -R ga:ga /opt/odoo

# Authenticate with Docker Hub to avoid rate limits
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

# Pre-pull Docker images to avoid rate limit issues during setup
echo "Pre-pulling Docker images..."
docker pull postgres:15 2>&1 | tail -3 || true
docker pull odoo:17 2>&1 | tail -3 || true

echo "=== Odoo Quality installation prerequisites complete ==="
