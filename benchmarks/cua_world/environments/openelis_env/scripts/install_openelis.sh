#!/bin/bash
# OpenELIS Global Installation Script (pre_start hook)
# Installs Docker, docker-compose-plugin (v2), Firefox, and UI automation tools.
# Pre-pulls all OpenELIS Docker images to speed up post_start.

set -euo pipefail

echo "=== Installing OpenELIS Global prerequisites ==="

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update

# Install Docker — use docker.io + docker-compose (v1 fallback) plus try v2 plugin.
# IMPORTANT: use docker-compose-plugin (v2) NOT docker-compose (v1) per cross-cutting patterns.
echo "Installing Docker + Compose..."
apt-get install -y docker.io
# Try docker-compose-plugin first (provides 'docker compose' v2)
apt-get install -y docker-compose-plugin 2>/dev/null \
    || apt-get install -y docker-compose-v2 2>/dev/null \
    || apt-get install -y docker-compose 2>/dev/null \
    || echo "WARNING: docker-compose install fell through; will rely on docker.io built-in"

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
    netcat-openbsd \
    libnss3-tools \
    dbus-x11 \
    libcanberra-gtk-module \
    libcanberra-gtk3-module \
    python3 \
    python3-requests

# Wait for Docker daemon to be fully ready
echo "Waiting for Docker daemon..."
for i in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        echo "Docker daemon is ready"
        break
    fi
    sleep 2
done

# Authenticate with Docker Hub to avoid rate limits
echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin 2>/dev/null || true

# Pre-pull all OpenELIS Docker images
echo "Pre-pulling OpenELIS Docker images (this may take several minutes)..."
docker pull itechuw/certgen:main || true
docker pull itechuw/openelis-global-2-database:develop || true
docker pull itechuw/openelis-global-2:develop || true
docker pull itechuw/openelis-global-2-fhir:develop || true
docker pull itechuw/openelis-global-2-frontend:develop || true
docker pull itechuw/openelis-global-2-proxy:develop || true
docker pull willfarrell/autoheal:1.2.0 || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== OpenELIS Installation Complete ==="
echo "Docker: $(docker --version 2>/dev/null || echo 'not found')"
# Detect which compose command is available
if docker compose version >/dev/null 2>&1; then
    echo "Docker Compose: $(docker compose version 2>/dev/null)"
elif command -v docker-compose >/dev/null 2>&1; then
    echo "Docker Compose (v1): $(docker-compose --version 2>/dev/null)"
fi
echo "Firefox: $(firefox --version 2>/dev/null || echo 'not found')"
echo "Images pulled:"
docker images --format "  {{.Repository}}:{{.Tag}} ({{.Size}})" 2>/dev/null | grep -E "itechuw|autoheal" || true
