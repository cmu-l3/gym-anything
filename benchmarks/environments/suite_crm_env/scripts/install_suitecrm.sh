#!/bin/bash
set -e

echo "=== Installing SuiteCRM Dependencies ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Docker
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# Install Docker Compose v2 plugin (v1 has ContainerConfig compat issues)
mkdir -p /usr/local/lib/docker/cli-plugins
COMPOSE_VER="v2.24.5"
curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version

# Install Firefox for GUI automation
apt-get install -y firefox

# Install GUI automation tools
apt-get install -y wmctrl xdotool x11-utils xclip

# Install utilities
apt-get install -y curl jq python3-pip scrot imagemagick

echo "=== SuiteCRM dependency installation complete ==="
