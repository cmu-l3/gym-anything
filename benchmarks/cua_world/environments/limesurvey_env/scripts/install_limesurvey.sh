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

echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Firefox: $(which firefox)"

echo ""
echo "LimeSurvey will be started via Docker in post_start hook"
