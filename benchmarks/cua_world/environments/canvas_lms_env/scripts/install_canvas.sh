#!/bin/bash
# Canvas LMS Installation Script (pre_start hook)
# Installs Docker and required dependencies for Canvas LMS
set -e

echo "=== Installing Canvas LMS Dependencies ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# ============================================================
# 1. Install Docker and Docker Compose
# ============================================================
echo "Installing Docker..."
apt-get install -y \
    docker.io \
    docker-compose \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

systemctl enable docker
systemctl start docker
usermod -aG docker ga

# ============================================================
# 2. Install Firefox and GUI automation tools
# ============================================================
echo "Installing Firefox and automation tools..."
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    jq \
    git \
    wget

# ============================================================
# 3. Install Python PostgreSQL connector for verification
# ============================================================
echo "Installing Python PostgreSQL connector..."
apt-get install -y python3-pip python3-psycopg2
pip3 install --no-cache-dir psycopg2-binary || true

# ============================================================
# 4. Create Canvas directory structure
# ============================================================
echo "Creating Canvas directory structure..."
mkdir -p /home/ga/canvas
mkdir -p /home/ga/canvas/data/postgres
mkdir -p /home/ga/canvas/data/redis
mkdir -p /home/ga/canvas/data/canvas_files
chown -R ga:ga /home/ga/canvas

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Canvas LMS Dependencies Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Firefox: $(which firefox)"
echo ""
echo "Canvas LMS will be configured in post_start hook"
