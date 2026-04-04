#!/bin/bash
set -e

echo "=== Installing Odoo Scheduling Environment Prerequisites ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install prerequisites
# Note: python3 xmlrpc is part of Python stdlib — no separate package needed
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    python3-pip \
    scrot \
    wmctrl \
    xdotool \
    wget \
    software-properties-common

# Note: Firefox (snap version) is pre-installed in the base image.
# The snap version works fine for Odoo access; task hooks use ensure_firefox()
# which handles snap lock artifacts via 2-attempt launch logic.

# Install Docker CE from official repository (docker-compose-plugin requires Docker CE, not docker.io)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Enable and start Docker daemon
systemctl enable docker
systemctl start docker

# Add ga user to docker group so they can run docker commands without sudo
usermod -aG docker ga

# Create Odoo working directory
mkdir -p /opt/odoo

# Copy config files to writable location (workspace mounts are read-only)
cp /workspace/config/docker-compose.yml /opt/odoo/
cp /workspace/config/odoo.conf /opt/odoo/

# Set ownership
chown -R ga:ga /opt/odoo

# Try Docker Hub authentication to avoid rate limits (optional)
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

# Pre-pull Docker images to avoid rate limit issues during setup
echo "Pre-pulling Docker images..."
docker pull postgres:15 2>&1 | tail -3 || true
docker pull odoo:17 2>&1 | tail -3 || true

echo "=== Odoo installation prerequisites complete ==="
