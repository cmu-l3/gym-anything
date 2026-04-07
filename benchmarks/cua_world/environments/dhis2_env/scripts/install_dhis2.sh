#!/bin/bash
# DHIS2 Installation Script (pre_start hook)
# Installs Docker, Firefox, and automation tools
set -e

echo "=== Installing DHIS2 Dependencies ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose
echo "Installing Docker and Docker Compose..."
apt-get install -y \
    docker.io \
    docker-compose \
    ca-certificates \
    gnupg \
    lsb-release

# Enable and start Docker
echo "Enabling Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga

# Install Firefox (for web UI access)
echo "Installing Firefox..."
apt-get install -y firefox

# Install automation and utility tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    wget \
    jq \
    imagemagick \
    scrot \
    python3-pip

# Authenticate with Docker Hub to avoid rate limits
echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin \
    && echo "Docker Hub auth successful" \
    || echo "Docker Hub auth failed (continuing anyway)"

# Pre-pull Docker images during install phase
if [ -f /workspace/config/docker-compose.yml ]; then
    mkdir -p /home/ga/dhis2
    cp /workspace/config/docker-compose.yml /home/ga/dhis2/
    cp /workspace/config/dhis.conf /home/ga/dhis2/ 2>/dev/null || true
    chown -R ga:ga /home/ga/dhis2
    cd /home/ga/dhis2
    docker-compose pull || echo "Warning: docker-compose pull failed (will retry in setup)"
fi

# Clean up apt cache to reduce image size
echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== DHIS2 Dependencies Installation Complete ==="
