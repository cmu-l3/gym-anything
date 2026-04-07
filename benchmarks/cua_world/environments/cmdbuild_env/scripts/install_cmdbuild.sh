#!/bin/bash
set -e

echo "=== Installing CMDBuild dependencies ==="

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
  python3-pip

systemctl enable docker
systemctl start docker

usermod -aG docker ga || true

# Pre-pull images to speed up post_start
echo "Pre-pulling Docker images..."
docker pull postgres:16-alpine || true
docker pull itmicus/cmdbuild:4.1.0 || true

echo "=== CMDBuild dependency installation complete ==="
