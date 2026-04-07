#!/bin/bash
set -euo pipefail

echo "=== Installing Bahmni environment dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
  docker.io \
  docker-compose \
  firefox \
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
  libcanberra-gtk3-module \
  mysql-client \
  libnss3-tools

systemctl enable docker
systemctl start docker

usermod -aG docker ga 2>/dev/null || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Bahmni dependency installation complete ==="
echo "Docker: $(docker --version 2>/dev/null || true)"
echo "Docker Compose: $(docker-compose --version 2>/dev/null || true)"
echo "Firefox: $(firefox --version 2>/dev/null || true)"
