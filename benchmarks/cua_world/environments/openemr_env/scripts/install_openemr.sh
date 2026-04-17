#!/bin/bash
# OpenEMR Installation Script (pre_start hook)
# Installs Docker - OpenEMR runs via official Docker container
# This is MUCH simpler and more reliable than manual LAMP setup

set -e

echo "=== Installing Docker for OpenEMR ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose
echo "Installing Docker..."
apt-get install -y docker.io docker-compose

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group (allows running docker without sudo)
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
    curl

# Install Python MySQL connector for verification scripts
apt-get install -y python3-pip python3-pymysql
pip3 install --no-cache-dir mysql-connector-python PyMySQL || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# ── Configure nested docker for overlay-on-overlay environments ──────────
# vfs storage driver avoids whiteout extraction failures in nested docker
# (docker-in-docker under --cap-drop ALL --privileged, or docker-in-QEMU).
if ! grep -q 'storage-driver' /etc/docker/daemon.json 2>/dev/null; then
    echo "Configuring docker storage driver: vfs"
    systemctl stop docker 2>/dev/null || true
    rm -rf /var/lib/docker/overlay2 /var/lib/docker/image 2>/dev/null
    mkdir -p /etc/docker
    echo '{"storage-driver": "vfs"}' > /etc/docker/daemon.json
    systemctl start docker
    for i in {1..30}; do
        docker info >/dev/null 2>&1 && break
        sleep 1
    done
fi

# ── Pre-pull OpenEMR images into the checkpoint ──────────────────────────
# Images are files on disk — safe to cache in QEMU/Docker checkpoints.
# This runs ONCE during checkpoint creation. Every subsequent run starts
# with images already cached, eliminating runtime pulls (and auth issues).
echo "Pre-pulling OpenEMR images (cached in checkpoint)..."
mkdir -p /home/ga/openemr
cp /workspace/config/docker-compose.yml /home/ga/openemr/
chown -R ga:ga /home/ga/openemr
cd /home/ga/openemr
docker-compose pull
echo "Images cached:"
docker images | grep -E "mariadb|openemr" | head -5

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Firefox: $(which firefox)"
echo "Images pre-pulled: $(docker images -q | wc -l)"
echo ""
echo "OpenEMR will be started via Docker in post_start hook"
