#!/bin/bash
set -euo pipefail

echo "=== Installing Mattermost environment dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
  docker.io \
  docker-compose \
  firefox \
  epiphany-browser \
  curl \
  jq \
  wmctrl \
  xdotool \
  scrot \
  imagemagick \
  x11-utils \
  xclip \
  python3 \
  python3-requests \
  netcat-openbsd \
  dbus-x11 \
  libcanberra-gtk-module \
  libcanberra-gtk3-module

systemctl enable docker
systemctl start docker

usermod -aG docker ga 2>/dev/null || true

# Wait for Docker to be fully ready
sleep 5

# Pre-pull Docker images for Mattermost
echo "Pre-pulling Docker images..."
docker pull mattermost/mattermost-team-edition:10.4 || true
docker pull postgres:15-alpine || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Mattermost dependency installation complete ==="
echo "Docker: $(docker --version 2>/dev/null || true)"
echo "Docker Compose: $(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true)"
echo "Firefox: $(firefox --version 2>/dev/null || true)"
