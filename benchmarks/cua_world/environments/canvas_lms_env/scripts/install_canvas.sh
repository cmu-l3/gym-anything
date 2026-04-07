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

# Configure Docker to NOT modify iptables rules.
# CRITICAL: Docker's iptables setup breaks QEMU's SSH port forwarding
# when Docker daemon restarts on checkpoint restore. With iptables disabled,
# we use host network mode in docker-compose instead.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DEOF'
{
  "iptables": false,
  "ip6tables": false
}
DEOF

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

# ============================================================
# 5. Create swap space (Canvas fat container is memory-hungry)
# ============================================================
echo "Creating 4GB swap file..."
fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab
echo "Swap enabled"

# ============================================================
# 6. Pre-pull Canvas Docker image (saves it in pre_start cache)
# ============================================================
echo "Setting up docker-compose for Canvas..."
cp /workspace/config/docker-compose.yml /home/ga/canvas/
chown -R ga:ga /home/ga/canvas

echo "Pre-pulling Canvas Docker image (this takes 3-5 minutes)..."
cd /home/ga/canvas
docker-compose pull 2>&1 || {
    echo "First pull attempt failed, retrying..."
    sleep 10
    docker-compose pull 2>&1 || echo "WARNING: Docker pull failed"
}
cd /

echo "Docker images:"
docker images | grep -i canvas || echo "(none)"

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Canvas LMS Dependencies Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Firefox: $(which firefox)"
echo ""
echo "Canvas Docker image pre-pulled. Post_start hook will start the container."
