#!/bin/bash
# OpenProject Installation Script (pre_start hook)
# Installs Docker, Firefox (snap), and UI automation tools.
# OpenProject itself is started as an all-in-one Docker container in post_start.

set -euo pipefail

echo "=== Installing OpenProject prerequisites ==="

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update

echo "Installing Docker + Compose v2..."
apt-get install -y docker.io docker-compose-v2

systemctl enable docker
systemctl start docker

# Allow ga user to run docker without sudo
usermod -aG docker ga || true

echo "Installing Firefox (snap) + automation tools..."
apt-get install -y \
  wmctrl \
  xdotool \
  x11-utils \
  xclip \
  imagemagick \
  curl \
  jq \
  ca-certificates \
  netcat-openbsd \
  python3 \
  python3-pip

# Install snap if not present
apt-get install -y snapd || true
systemctl enable snapd || true
systemctl start snapd || true

# Install Firefox via snap (matches pattern used in wger_env and other envs)
snap install firefox 2>/dev/null || true

# Install python requests for scripting
pip3 install --no-cache-dir requests 2>/dev/null || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker: $(docker --version 2>/dev/null || true)"
echo "Docker Compose: $(docker compose version 2>/dev/null || true)"
