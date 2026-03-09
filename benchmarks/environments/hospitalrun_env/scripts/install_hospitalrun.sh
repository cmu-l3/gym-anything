#!/bin/bash
set -e

echo "=== Installing HospitalRun dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Docker and basic tools
apt-get install -y \
    docker.io \
    curl \
    wget \
    jq \
    git \
    python3-pip \
    scrot \
    imagemagick \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    firefox \
    net-tools \
    lsof

# Enable and start Docker daemon
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
for i in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        echo "Docker is ready"
        break
    fi
    sleep 2
done

# Add ga user to docker group
usermod -aG docker ga

# Install Docker Compose v2 (critical: NOT v1 which has ContainerConfig bug)
COMPOSE_VER="v2.24.5"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Verify compose v2
docker compose version

echo "=== HospitalRun dependencies installation complete ==="
