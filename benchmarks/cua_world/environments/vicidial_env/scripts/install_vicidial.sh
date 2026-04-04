#!/bin/bash
set -e

echo "=== Installing Vicidial environment dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
  docker.io \
  docker-compose \
  firefox \
  curl \
  wget \
  jq \
  wmctrl \
  xdotool \
  scrot \
  imagemagick \
  x11-utils \
  xclip \
  python3 \
  python3-pip

systemctl enable docker
systemctl start docker

usermod -aG docker ga 2>/dev/null || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Vicidial dependency installation complete ==="

