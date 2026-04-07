#!/bin/bash
set -e

echo "=== Installing Odoo CRM Environment Dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install prerequisites
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Install Docker CE from official repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ga

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

# Authenticate with Docker Hub to avoid rate limits
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

# Pre-pull Docker images to avoid rate limit issues during setup
echo "Pre-pulling Docker images..."
docker pull postgres:15 2>&1 | tail -3 || true
docker pull odoo:17.0 2>&1 | tail -3 || true

echo "=== Odoo CRM Installation complete ==="
