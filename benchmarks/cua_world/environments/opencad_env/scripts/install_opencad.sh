#!/bin/bash
# Do NOT use set -e: individual failures should not abort the entire install
echo "=== Installing OpenCAD dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Install Docker and Docker Compose
apt-get install -y docker.io docker-compose curl wget jq git unzip

# Enable and start Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# Install Firefox and GUI automation tools
apt-get install -y firefox wmctrl xdotool imagemagick

# Install Python MySQL connector for verification
apt-get install -y python3-pip
pip3 install pymysql

# Pre-pull Docker images to avoid timeout during setup
echo "=== Pre-pulling Docker images ==="
docker pull mysql:5.7
docker pull php:7.3-apache

echo "=== Downloading OpenCAD source code ==="
# Download the stable release of OpenCAD-php
cd /tmp
wget -q https://github.com/opencad-app/OpenCAD-php/archive/refs/heads/release/stable.zip -O opencad.zip
unzip -q opencad.zip
mv OpenCAD-php-release-stable /opt/opencad-src

echo "=== OpenCAD installation complete ==="
