#!/bin/bash
# Docker Engine Installation Script (pre_start hook)
# Installs Docker Engine, Docker Compose, Trivy (security scanner),
# and all supporting tools needed for Docker CLI professional workflows.

set -e

echo "=== Installing Docker CLI Environment ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "[1/6] Updating package lists..."
apt-get update

# Install prerequisites
echo "[2/6] Installing system prerequisites..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    wget \
    git \
    jq \
    vim \
    nano \
    htop \
    netcat-openbsd \
    iputils-ping \
    net-tools \
    psmisc \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    postgresql-client \
    openssl \
    gnome-terminal \
    wmctrl \
    xdotool \
    x11-utils \
    scrot \
    imagemagick

# Install Docker Engine
echo "[3/6] Installing Docker Engine..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Also install standalone docker-compose v2 binary
echo "Installing docker-compose standalone..."
COMPOSE_VERSION="v2.24.5"
curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose 2>/dev/null || \
    apt-get install -y docker-compose 2>/dev/null || true
chmod +x /usr/local/bin/docker-compose 2>/dev/null || true

# Enable Docker service
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Install Trivy security scanner
echo "[4/6] Installing Trivy vulnerability scanner..."
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
    gpg --dearmor | tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb \
    $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/trivy.list > /dev/null
apt-get update
apt-get install -y trivy

# Download Trivy DB now (cached, so tasks don't need internet)
echo "Pre-downloading Trivy vulnerability database..."
trivy image --download-db-only 2>/dev/null || true

# Install Python packages needed for tasks and verification
echo "[5/6] Installing Python packages..."
pip3 install --no-cache-dir --break-system-packages \
    requests \
    flask \
    pytest \
    pytest-cov \
    psycopg2-binary \
    redis \
    httpx 2>/dev/null || \
pip3 install --no-cache-dir \
    requests \
    flask \
    pytest \
    pytest-cov \
    psycopg2-binary \
    redis \
    httpx 2>/dev/null || true

# Install npm packages needed for tasks
echo "Installing npm packages..."
npm install -g \
    express \
    nodemon \
    mocha \
    nyc 2>/dev/null || true

# Install htpasswd for registry auth
apt-get install -y apache2-utils 2>/dev/null || true

# Clean up
echo "[6/6] Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Docker CLI Environment Installed ==="
echo "Docker version: $(docker --version 2>/dev/null || echo 'pending systemd start')"
echo "Docker Compose version: $(docker compose version 2>/dev/null || echo 'pending systemd start')"
echo "Trivy version: $(trivy --version 2>/dev/null | head -1 || echo 'installed')"
echo ""
