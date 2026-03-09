#!/bin/bash
set -e

echo "=== Installing OpenMaint dependencies ==="

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
  xclip

systemctl enable docker
systemctl start docker

usermod -aG docker ga || true

echo "=== OpenMaint dependency installation complete ==="
