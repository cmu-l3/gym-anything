#!/bin/bash
set -e

echo "=== Installing Eramba Dependencies ==="

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
# Also symlink to Ubuntu docker.io plugin directory so 'docker compose' works
mkdir -p /usr/lib/docker/cli-plugins
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/lib/docker/cli-plugins/docker-compose
# Verify
docker compose version

# Install Firefox for GUI automation
apt-get install -y firefox

# Install GUI automation tools
apt-get install -y wmctrl xdotool x11-utils xclip

# Install NSS tools for managing Firefox cert database (needed for self-signed cert acceptance)
apt-get install -y libnss3-tools

# Install utilities
apt-get install -y curl jq python3-pip scrot imagemagick openssl

echo "=== Eramba dependency installation complete ==="
