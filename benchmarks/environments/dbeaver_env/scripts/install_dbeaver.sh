#!/bin/bash
# DBeaver Community Edition Installation Script (pre_start hook)
# Installs DBeaver CE and SQLite for database management tasks

set -e

echo "=== Installing DBeaver Community Edition ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Java (required by DBeaver)
echo "Installing Java..."
apt-get install -y default-jdk

# Add DBeaver repository and install
echo "Adding DBeaver repository..."
curl -fsSL https://dbeaver.io/debs/dbeaver.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/dbeaver.gpg
echo "deb https://dbeaver.io/debs/dbeaver-ce /" | tee /etc/apt/sources.list.d/dbeaver.list

apt-get update

echo "Installing DBeaver Community Edition..."
apt-get install -y dbeaver-ce

# Install SQLite (for sample database)
echo "Installing SQLite..."
apt-get install -y sqlite3

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    wget \
    unzip

# Install Python packages for verification scripts
apt-get install -y python3-pip
pip3 install --no-cache-dir --break-system-packages || pip3 install --no-cache-dir || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "DBeaver: $(which dbeaver-ce)"
echo "SQLite version: $(sqlite3 --version)"
echo "Java version: $(java -version 2>&1 | head -1)"
echo ""
echo "DBeaver will be configured in post_start hook"
