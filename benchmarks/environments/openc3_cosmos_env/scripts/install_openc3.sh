#!/bin/bash
# OpenC3 COSMOS Installation Script (pre_start hook)
# Installs Docker CE with Compose v2, clones cosmos-project, and pre-pulls images
set -e

echo "=== Installing OpenC3 COSMOS ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install prerequisites
echo "Installing prerequisites..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq \
    software-properties-common

# Install Docker CE from official Docker repository (includes compose v2)
echo "Adding Docker official GPG key and repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update

echo "Installing Docker CE and Docker Compose plugin..."
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
echo "Waiting for Docker daemon..."
DOCKER_TIMEOUT=30
DOCKER_ELAPSED=0
while [ $DOCKER_ELAPSED -lt $DOCKER_TIMEOUT ]; do
    if docker info > /dev/null 2>&1; then
        echo "Docker daemon is ready"
        break
    fi
    sleep 2
    DOCKER_ELAPSED=$((DOCKER_ELAPSED + 2))
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
    imagemagick \
    scrot

# Install Python dependencies for verification
apt-get install -y python3-pip
pip3 install --no-cache-dir requests || true

# Clone the OpenC3 COSMOS project
echo "Cloning OpenC3 COSMOS project..."
cd /home/ga
git clone https://github.com/OpenC3/cosmos-project.git cosmos
cd cosmos

# Ensure the demo is enabled (INST simulated satellite target)
if grep -q "^OPENC3_DEMO" .env; then
    sed -i 's/^OPENC3_DEMO=.*/OPENC3_DEMO=1/' .env
else
    echo "OPENC3_DEMO=1" >> .env
fi

# Ensure local mode is enabled
if grep -q "^OPENC3_LOCAL_MODE" .env; then
    sed -i 's/^OPENC3_LOCAL_MODE=.*/OPENC3_LOCAL_MODE=1/' .env
else
    echo "OPENC3_LOCAL_MODE=1" >> .env
fi

# Make openc3.sh executable
chmod +x openc3.sh

# Pre-pull Docker images to save time during setup
echo "Pre-pulling OpenC3 Docker images (this may take several minutes)..."
docker compose pull 2>&1 || echo "WARNING: Some images failed to pull, will retry during setup"

# Set ownership
chown -R ga:ga /home/ga/cosmos

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== OpenC3 COSMOS Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version 2>/dev/null || echo 'not found')"
echo "Firefox: $(which firefox)"
echo "Git version: $(git --version)"
echo ""
echo "COSMOS project cloned to: /home/ga/cosmos"
echo "COSMOS will be started via openc3.sh in post_start hook"
