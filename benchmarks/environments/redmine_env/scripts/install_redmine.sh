#!/bin/bash
# Redmine Installation Script (pre_start hook)
# Installs Docker (Redmine runs via official Docker image), Firefox, and UI automation tools.

set -euo pipefail

echo "=== Installing Redmine prerequisites ==="

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update

echo "Installing Docker + Compose v2..."
apt-get install -y docker.io docker-compose-v2

systemctl enable docker
systemctl start docker

# Allow ga user to run docker without sudo
usermod -aG docker ga || true

echo "Installing Firefox + automation tools..."
apt-get install -y \
  firefox \
  wmctrl \
  xdotool \
  x11-utils \
  xclip \
  scrot \
  imagemagick \
  curl \
  jq \
  ca-certificates \
  netcat-openbsd

echo "Installing Python runtime helpers..."
apt-get install -y python3 python3-pip

pip3 install --no-cache-dir requests >/dev/null 2>&1 || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Complete ==="
echo "Docker: $(docker --version 2>/dev/null || true)"
echo "Docker Compose: $(docker compose version 2>/dev/null || true)"
echo "Firefox: $(command -v firefox 2>/dev/null || true)"
