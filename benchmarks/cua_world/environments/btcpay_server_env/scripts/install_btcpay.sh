#!/bin/bash
set -e

echo "=== Installing BTCPay Server Dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Docker and base packages
apt-get install -y \
    docker.io \
    curl \
    jq \
    wget \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    python3-pip \
    scrot

# Install Docker Compose v2 plugin (not available in Ubuntu 22.04 default repos)
echo "Installing Docker Compose v2 plugin..."
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/v2.29.1/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Wait for Docker daemon to be responsive
echo "Waiting for Docker daemon..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if docker info > /dev/null 2>&1; then
        echo "Docker daemon ready after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: Docker daemon not ready after ${TIMEOUT}s"
fi

# Login to DockerHub if credentials are available (avoid rate limiting)
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin || true
fi

# Pre-pull Docker images to speed up post_start
echo "Pre-pulling Docker images..."
docker pull postgres:16-alpine || true
docker pull btcpayserver/bitcoin:29.1 || true
docker pull nicolasdorier/nbxplorer:2.5.30 || true
docker pull btcpayserver/btcpayserver:2.3.7 || true

echo "=== BTCPay Server installation complete ==="
