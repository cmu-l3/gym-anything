#!/bin/bash
set -e

echo "=== Installing wger dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install core utilities
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    wget \
    python3 \
    python3-pip \
    wmctrl \
    xdotool \
    imagemagick \
    x11-apps \
    net-tools

# Install Firefox (snap-based on Ubuntu 22+)
# firefox may already be installed; if not, install it
which firefox >/dev/null 2>&1 || apt-get install -y firefox

echo "=== Installing Docker CE ==="
# Remove old docker if present
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add ga user to docker group so it can run docker without sudo
usermod -aG docker ga

# Enable and start Docker service
systemctl enable docker
systemctl start docker

# Authenticate with Docker Hub to avoid rate limits during pull
echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin \
    && echo "Docker Hub auth successful" \
    || echo "Docker Hub auth failed (continuing anyway)"

# Pre-pull Docker images during install phase (faster setup later)
WGER_DIR="/home/ga/wger"
mkdir -p "$WGER_DIR"
if [ -f /workspace/config/docker-compose.yml ]; then
    cp /workspace/config/docker-compose.yml "$WGER_DIR/"
    cp /workspace/config/prod.env "$WGER_DIR/" 2>/dev/null || true
    cp /workspace/config/nginx.conf "$WGER_DIR/" 2>/dev/null || true
    chown -R ga:ga "$WGER_DIR"
    cd "$WGER_DIR"
    docker compose pull || echo "Warning: docker compose pull failed (will retry in setup)"
fi

echo "=== Docker installed: $(docker --version) ==="
echo "=== wger dependencies installation complete ==="
