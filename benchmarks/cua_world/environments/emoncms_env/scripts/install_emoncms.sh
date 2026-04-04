#!/bin/bash
set -e

echo "=== Installing Emoncms dependencies ==="

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
    net-tools \
    jq

# Install Firefox (snap-based on Ubuntu 22+)
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

# Add ga user to docker group
usermod -aG docker ga

# Enable and start Docker service
systemctl enable docker
systemctl start docker

echo "=== Docker installed: $(docker --version) ==="
echo "=== Emoncms dependencies installation complete ==="
