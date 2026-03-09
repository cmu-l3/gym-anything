#!/bin/bash
# OrangeHRM Pre-Start Hook: Install Docker, browser, and GUI automation tools
set -euo pipefail

echo "=== Installing OrangeHRM dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq

# Core tools
apt-get install -y \
    curl wget ca-certificates gnupg lsb-release \
    jq expect \
    wmctrl xdotool scrot imagemagick \
    python3 python3-pip \
    net-tools

# Docker Engine (v2 plugin pattern)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io

# Docker Compose v2 as plugin
COMPOSE_VERSION="v2.24.5"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL \
    "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Enable Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# Firefox (snap or apt)
if command -v snap >/dev/null 2>&1; then
    snap install firefox 2>/dev/null || apt-get install -y firefox 2>/dev/null || true
else
    apt-get install -y firefox 2>/dev/null || true
fi

echo "=== OrangeHRM dependency installation complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"
