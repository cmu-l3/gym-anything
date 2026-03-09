#!/bin/bash
# JFrog Artifactory Installation Script (pre_start hook)
# Installs Docker (from official Docker apt repo), Firefox, and supporting tools
set -e

echo "=== Installing JFrog Artifactory Dependencies ==="

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update

# ============================================================
# 1. Install prerequisite packages for Docker repo setup
# ============================================================
echo "Installing prerequisite packages..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common

# ============================================================
# 2. Add Docker's official GPG key and apt repository
#    (docker-compose-plugin is only in Docker's official repo,
#     not in Ubuntu's default repos)
# ============================================================
echo "Adding Docker official apt repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Updating package lists with Docker repo..."
apt-get update

# ============================================================
# 3. Install Docker CE and Docker Compose plugin (v2)
# ============================================================
echo "Installing Docker CE and Docker Compose plugin..."
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ga

echo "Docker installed: $(docker --version)"
echo "Docker Compose installed: $(docker compose version)"

# ============================================================
# 4. Install Firefox and GUI automation tools
# ============================================================
echo "Installing Firefox and GUI automation tools..."
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot \
    jq \
    wget \
    unzip \
    imagemagick \
    x11-apps \
    python3-pip

pip3 install --no-cache-dir requests 2>/dev/null || true

# ============================================================
# 5. Create working directories
# ============================================================
echo "Creating working directories..."
mkdir -p /home/ga/artifactory
mkdir -p /home/ga/artifacts
chown -R ga:ga /home/ga/artifactory
chown -R ga:ga /home/ga/artifacts

# ============================================================
# 6. Configure kernel settings required by Artifactory JVM
# ============================================================
echo "Configuring kernel settings..."
sysctl -w vm.max_map_count=262144 2>/dev/null || true

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== JFrog Artifactory Dependencies Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"
echo "Firefox: $(which firefox)"
echo ""
echo "JFrog Artifactory will be started via Docker in post_start hook"
