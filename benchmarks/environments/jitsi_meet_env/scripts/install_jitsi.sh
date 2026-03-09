#!/bin/bash
set -e

echo "=== Installing Jitsi Meet dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install core dependencies
apt-get install -y \
    curl \
    wget \
    jq \
    python3 \
    python3-pip \
    python3-requests \
    netcat-openbsd \
    wmctrl \
    xdotool \
    scrot \
    imagemagick \
    x11-utils \
    xclip \
    dbus-x11 \
    firefox \
    epiphany-browser \
    libgtk-3-0 \
    libdbus-glib-1-2

# Install Docker (docker.io) and docker-compose-v2
apt-get install -y \
    docker.io \
    docker-compose-v2

# Enable Docker on boot
systemctl enable docker
systemctl start docker

# Add ga user to docker group so it can run docker without sudo
usermod -aG docker ga

# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Jitsi Meet dependencies installation complete ==="
