#!/bin/bash
# set -euo pipefail

# Prevent ALL interactive prompts during installation
export DEBIAN_FRONTEND=noninteractive

echo "=== Installing ONLYOFFICE Desktop Editors and related packages ==="

# Update package manager
apt-get update -qq

# Install debconf-utils first (needed for debconf-set-selections)
apt-get install -y debconf-utils

# Pre-accept ALL EULAs and licenses before any package installation
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
echo ttf-mscorefonts-installer msttcorefonts/present-mscorefonts-eula note | debconf-set-selections

# Install prerequisites
echo "Installing prerequisites..."
apt-get install -y \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    curl

# Add ONLYOFFICE GPG key
echo "Adding ONLYOFFICE repository..."
mkdir -p /usr/share/keyrings
wget -qO - https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --dearmor > /usr/share/keyrings/onlyoffice.gpg

# Add ONLYOFFICE repository
echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" | \
    tee /etc/apt/sources.list.d/onlyoffice.list

# Update package list with new repository
apt-get update

# Install ONLYOFFICE Desktop Editors
echo "Installing ONLYOFFICE Desktop Editors..."
apt-get install -y onlyoffice-desktopeditors

# Install Python libraries for document parsing
echo "Installing Python libraries for document verification..."
apt-get install -y \
    python3-pip \
    python3-dev \
    python3-lxml

pip3 install --no-cache-dir \
    python-docx \
    openpyxl \
    python-pptx \
    odfpy \
    pandas \
    xlrd \
    xlwt \
    lxml \
    beautifulsoup4

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install file handling utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    p7zip-full \
    poppler-utils \
    unoconv

# Install additional fonts for better compatibility
echo "Installing Microsoft-compatible fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-liberation2 \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-crosextra-carlito \
    fonts-crosextra-caladea \
    ttf-mscorefonts-installer

# Install LibreOffice for format conversion fallback
echo "Installing LibreOffice for format conversion..."
apt-get install -y \
    libreoffice-core-nogui \
    libreoffice-writer-nogui \
    libreoffice-calc-nogui \
    libreoffice-impress-nogui

# Configure swap space for memory-intensive operations
echo "Configuring swap space..."
if [ ! -f /swapfile ]; then
    # Create 4GB swap file
    fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "✅ Swap file created (4GB)"
else
    echo "ℹ️  Swap file already exists"
fi

# Configure kernel memory parameters for ONLYOFFICE
echo "Configuring kernel memory parameters..."

# Set swappiness (lower = less aggressive swapping, better for desktop apps)
sysctl -w vm.swappiness=10
echo "vm.swappiness=10" >> /etc/sysctl.conf

# Set memory overcommit mode (1 = always overcommit, prevents OOM for large apps)
sysctl -w vm.overcommit_memory=1
echo "vm.overcommit_memory=1" >> /etc/sysctl.conf

# Increase shared memory limits for ONLYOFFICE rendering
sysctl -w kernel.shmmax=2147483648  # 2GB
sysctl -w kernel.shmall=524288      # 2GB in pages
echo "kernel.shmmax=2147483648" >> /etc/sysctl.conf
echo "kernel.shmall=524288" >> /etc/sysctl.conf

# Disable OOM killer for critical system processes (but not ONLYOFFICE itself)
echo "vm.oom-kill=1" >> /etc/sysctl.conf

echo "✅ Kernel memory parameters configured"

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== ONLYOFFICE Desktop Editors installation completed ==="

# Verify installation
if command -v onlyoffice-desktopeditors &> /dev/null; then
    echo "✅ ONLYOFFICE installed successfully"
    onlyoffice-desktopeditors --version || echo "Version check skipped (headless environment)"
else
    echo "❌ ONLYOFFICE installation may have failed"
    exit 1
fi
