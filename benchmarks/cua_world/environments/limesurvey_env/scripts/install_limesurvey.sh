#!/bin/bash
set -e

echo "=== Installing LimeSurvey Environment ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Docker and Docker Compose
echo "Installing Docker..."
apt-get install -y \
    docker.io \
    docker-compose \
    curl \
    wget \
    jq

# Start Docker service
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Install Firefox and GUI tools
echo "Installing Firefox and GUI tools..."
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    python3-mysql.connector

# Install Python MySQL connector
pip3 install mysql-connector-python pymysql

# Wait for Docker to be fully ready
sleep 5
echo "Docker status:"
systemctl status docker --no-pager || true

# Authenticate with Docker Hub to avoid rate limits
echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin 2>/dev/null || true

# Pre-pull Docker images for LimeSurvey
echo "Pre-pulling Docker images..."
docker pull martialblog/limesurvey:6-apache || true
docker pull mysql:8.0 || true

echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Firefox: $(which firefox)"

echo ""
echo "LimeSurvey will be started via Docker in post_start hook"
