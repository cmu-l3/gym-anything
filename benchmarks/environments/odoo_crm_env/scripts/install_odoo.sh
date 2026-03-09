#!/bin/bash
set -e

echo "=== Installing Odoo CRM Environment Dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Docker
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# Install Docker Compose v2 plugin
apt-get install -y docker-compose-plugin || {
    # Fallback: manual install
    mkdir -p /usr/local/lib/docker/cli-plugins
    COMPOSE_VER="v2.24.5"
    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
}

# Verify docker compose v2 works
docker compose version

# Install browser and automation tools
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    jq \
    python3-pip \
    scrot \
    imagemagick

# Install Python xmlrpc (for seeding data via Odoo API)
python3 -c "import xmlrpc.client; print('xmlrpc.client available')"

echo "=== Odoo CRM Installation complete ==="
