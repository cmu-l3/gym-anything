#!/bin/bash
set -e

echo "=== Installing FreeScout Dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Docker and docker-compose
apt-get install -y docker.io docker-compose

# Fallback: if docker-compose not found, try docker compose plugin
if ! command -v docker-compose &>/dev/null; then
    if docker compose version &>/dev/null 2>&1; then
        cat > /usr/local/bin/docker-compose << 'DCEOF'
#!/bin/bash
exec docker compose "$@"
DCEOF
        chmod +x /usr/local/bin/docker-compose
    else
        curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
fi

# Start Docker service
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Install Firefox and GUI tools
apt-get install -y firefox wmctrl xdotool imagemagick jq curl

# Install Python MySQL connector for verification
apt-get install -y python3-pip
pip3 install --no-cache-dir PyMySQL 2>/dev/null || true

# Pre-pull Docker images to avoid timeout during post_start
echo "=== Pre-pulling Docker images ==="
docker pull mariadb:10.11 || echo "WARNING: Failed to pull mariadb"
docker pull tiredofit/freescout:latest || echo "WARNING: Failed to pull freescout"

echo "=== FreeScout installation complete ==="
