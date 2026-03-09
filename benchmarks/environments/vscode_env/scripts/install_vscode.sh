#!/bin/bash
# set -euo pipefail

echo "=== Installing VSCode and related packages ==="

# Update package manager
apt-get update

# Install dependencies
echo "Installing dependencies..."
apt-get install -y \
    wget \
    gpg \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common

# Add Microsoft GPG key and repository
echo "Adding Microsoft repository..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list

# Update and install VSCode
apt-get update
apt-get install -y code

echo "VSCode installed: $(code --version | head -1)"

# Install language runtimes and tools
echo "Installing language runtimes and development tools..."

# Python 3
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev

# Node.js (install latest LTS via NodeSource)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Java
apt-get install -y \
    openjdk-17-jdk \
    openjdk-17-jre

# Build tools
apt-get install -y \
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    git

# GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    imagemagick

# Install common Python packages
echo "Installing Python packages..."
pip3 install --no-cache-dir \
    pylint \
    flake8 \
    black \
    pytest \
    requests \
    numpy \
    pandas

# Install common Node.js packages globally
echo "Installing Node.js packages..."
npm install -g \
    eslint \
    prettier \
    typescript \
    ts-node \
    nodemon

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== VSCode installation completed ==="
