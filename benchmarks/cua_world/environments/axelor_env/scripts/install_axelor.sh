#!/bin/bash
set -e

echo "=== Installing Axelor Dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Install Docker
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# Install Docker Compose v2 plugin
mkdir -p /usr/local/lib/docker/cli-plugins
COMPOSE_VER="v2.24.5"
curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version

# Install Firefox
apt-get install -y firefox

# Install GUI automation tools
apt-get install -y wmctrl xdotool x11-utils xclip

# Install utilities
apt-get install -y curl jq python3-pip scrot imagemagick

# Docker Hub authentication
echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin 2>/dev/null || true

echo "=== Axelor dependency installation complete ==="
