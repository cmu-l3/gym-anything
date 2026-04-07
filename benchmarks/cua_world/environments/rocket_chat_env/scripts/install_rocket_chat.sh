#!/bin/bash
set -euo pipefail

echo "=== Installing Rocket.Chat environment dependencies ==="

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

# Authenticate with Docker Hub to avoid rate limits
echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin 2>/dev/null || true

# Pre-pull Docker images for Rocket.Chat
echo "Pre-pulling Docker images..."
docker pull registry.rocket.chat/rocketchat/rocket.chat:8.1.0 || true
docker pull docker.io/mongodb/mongodb-community-server:8.2-ubi8 || true
docker pull docker.io/nats:2.11-alpine || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Rocket.Chat dependency installation complete ==="
echo "Docker: $(docker --version 2>/dev/null || true)"
echo "Docker Compose: $(docker-compose --version 2>/dev/null || true)"
echo "Firefox: $(firefox --version 2>/dev/null || true)"
