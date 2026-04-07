#!/bin/bash
# VistA Environment Installation Script (pre_start hook)
# Installs Docker for VistA VEHU server and Firefox for web interface

set -e

echo "=== Installing VistA Environment ==="

# Configure apt for non-interactive installation
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update -y

# Install Docker
echo "Installing Docker..."
if ! command -v docker &> /dev/null; then
    apt-get install -y docker.io
    systemctl enable docker
    systemctl start docker
    # Add ga user to docker group
    usermod -aG docker ga || true
fi

# Install Firefox and GUI tools
echo "Installing Firefox and GUI automation tools..."
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    imagemagick \
    curl \
    netcat-openbsd \
    jq

# Install additional fonts for better rendering
echo "Installing fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-dejavu-core \
    || true

# Pre-pull VistA VEHU Docker image (to speed up post_start)
echo "Pre-pulling VistA VEHU Docker image..."
docker pull worldvista/vehu:latest || echo "Warning: Could not pre-pull image (will be pulled in setup)"

# Create workspace directories
echo "Setting up workspace directories..."
mkdir -p /workspace/scripts
mkdir -p /workspace/tasks
mkdir -p /workspace/config
mkdir -p /workspace/utils

# Set permissions
chown -R ga:ga /workspace 2>/dev/null || true

echo ""
echo "=== VistA Environment Installation Complete ==="
echo ""
echo "Installed components:"
echo "  - Docker (for VistA VEHU container)"
echo "  - Firefox (for YDBGui web interface)"
echo "  - GUI automation tools (wmctrl, xdotool)"
echo "  - ImageMagick (for screenshots)"
echo ""
echo "Post-start will:"
echo "  - Start VistA VEHU Docker container"
echo "  - Configure YDBGui web interface (no authentication)"
echo "  - Launch Firefox with YDBGui Dashboard"
echo ""
