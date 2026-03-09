#!/bin/bash
set -euo pipefail

echo "=== Installing SEB Server Environment ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install essential tools
apt-get install -y \
    curl \
    wget \
    gnupg \
    ca-certificates \
    lsb-release \
    software-properties-common \
    apt-transport-https

# Install GUI automation tools
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    scrot \
    imagemagick

# Install Python tools for verification
apt-get install -y \
    python3-pip \
    python3-pymysql \
    jq

pip3 install --no-cache-dir PyMySQL requests

# ============================================================
# Install Docker CE with docker-compose-plugin (v2, NOT v1)
# ============================================================
echo "=== Installing Docker CE ==="

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Fix docker config permissions for ga user
mkdir -p /home/ga/.docker
chown -R ga:ga /home/ga/.docker

echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"

# ============================================================
# Authenticate with Docker Hub to avoid rate limits
# ============================================================
if [ -f /workspace/config/.dockerhub_credentials ]; then
    echo "=== Authenticating with Docker Hub ==="
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || \
        echo "WARNING: Docker Hub authentication failed, continuing without auth"
else
    echo "WARNING: No Docker Hub credentials found, may hit rate limits"
fi

# ============================================================
# Pre-pull Docker images
# ============================================================
echo "=== Pulling Docker images ==="
docker pull mariadb:10.5 || echo "WARNING: Failed to pull mariadb:10.5"
docker pull anhefti/seb-server:v2.2-stable || echo "WARNING: Failed to pull seb-server"

# ============================================================
# Install Firefox (if not already installed as snap)
# ============================================================
echo "=== Ensuring Firefox is available ==="
if ! command -v firefox &>/dev/null; then
    apt-get install -y firefox || snap install firefox || echo "WARNING: Could not install Firefox"
fi

# ============================================================
# Prepare Docker Compose working directory
# ============================================================
echo "=== Setting up Docker Compose directory ==="
mkdir -p /opt/seb-server
cp /workspace/config/docker-compose.yml /opt/seb-server/
cp /workspace/config/mariadb_config.cnf /opt/seb-server/
chown -R root:root /opt/seb-server

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== SEB Server installation complete ==="
