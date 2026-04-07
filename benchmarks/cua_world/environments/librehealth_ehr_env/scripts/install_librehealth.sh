#!/bin/bash
# LibreHealth EHR Installation Script (pre_start hook)
# Installs Docker - LibreHealth EHR runs via official Docker containers
# Uses NHANES real patient data from the official lh-ehr repository

set -e

echo "=== Installing Docker for LibreHealth EHR ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose v2
# On Ubuntu Jammy: use docker.io + docker-compose-v2 (docker-compose-plugin is unavailable)
echo "Installing Docker..."
apt-get install -y docker.io docker-compose-v2

# Also install legacy docker-compose v1 as fallback
apt-get install -y docker-compose 2>/dev/null || true

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Install Firefox browser (non-snap version via apt)
echo "Installing Firefox..."
apt-get install -y firefox

# Install GUI automation and utility tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    wget \
    imagemagick \
    scrot \
    python3-pip \
    python3-pymysql \
    jq

# Install Python MySQL connector for verification scripts
pip3 install --no-cache-dir mysql-connector-python PyMySQL 2>/dev/null || true

# Install gawk (required by LibreHealth dev scripts)
apt-get install -y gawk

# Pre-pull Docker images with Google mirror fallback (avoids Docker Hub rate limits)
echo "Pre-pulling LibreHealth EHR Docker images..."
docker pull registry.gitlab.com/librehealth/ehr/lh-ehr:latest 2>/dev/null || \
    echo "WARNING: Could not pre-pull lh-ehr image, will pull during setup"

# mariadb - try Docker Hub first, then Google mirror
docker pull mariadb:10.3 2>/dev/null || {
    echo "Docker Hub rate limited, trying Google mirror for mariadb..."
    docker pull mirror.gcr.io/library/mariadb:10.3 2>/dev/null && \
        docker tag mirror.gcr.io/library/mariadb:10.3 mariadb:10.3 || \
        echo "WARNING: Could not pre-pull mariadb image"
}

# adminer - try Docker Hub first, then Google mirror
docker pull adminer:4 2>/dev/null || {
    echo "Docker Hub rate limited, trying Google mirror for adminer..."
    docker pull mirror.gcr.io/library/adminer:4 2>/dev/null && \
        docker tag mirror.gcr.io/library/adminer:4 adminer:4 || \
        echo "WARNING: Could not pre-pull adminer image"
}

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Installation Summary ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo 'unknown')"
echo "Firefox: $(which firefox)"
echo ""
echo "LibreHealth EHR will be started via Docker in post_start hook"
