#!/bin/bash
# pre_start hook: Install Docker, Docker Compose, and browser for Wazuh SIEM environment
set -e

echo "=== Installing Wazuh environment dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install system tools
apt-get install -y \
    curl \
    wget \
    git \
    jq \
    python3-pip \
    scrot \
    imagemagick \
    xdotool \
    wmctrl \
    x11-utils \
    net-tools \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    procps \
    htop \
    vim \
    openssh-client

# Install Docker Engine
echo "=== Installing Docker Engine ==="
# Remove any old versions
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Verify Docker Compose v2
docker compose version
echo "Docker Compose v2 installed successfully"

# Set vm.max_map_count for Wazuh indexer (OpenSearch/Elasticsearch requirement)
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -w vm.max_map_count=262144

# Install Firefox (for dashboard access)
# Firefox may be installed as snap or apt - handle both
if ! which firefox >/dev/null 2>&1; then
    # Try apt first
    apt-get install -y firefox 2>/dev/null || \
    snap install firefox 2>/dev/null || \
    true
fi

echo "=== Wazuh environment dependencies installed successfully ==="
