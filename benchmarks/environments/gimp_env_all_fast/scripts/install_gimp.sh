#!/bin/bash
set -euo pipefail

# ======= FIX: Configure faster APT mirrors =======
echo "Configuring faster APT mirrors for Azure infrastructure..."

# Backup original sources if they exist
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
fi


# Configure apt to be faster and more reliable
sudo cat > /etc/apt/apt.conf.d/99custom << 'APT_CONF_EOF'
# Speed up apt by reducing retries and timeouts
Acquire::Retries "3";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::ftp::Timeout "10";

# Use parallel downloads
Acquire::Queue-Mode "access";

# Reduce cache validity
Acquire::http::No-Cache "false";
APT_CONF_EOF

echo "Mirror configuration updated to use Azure mirrors"

echo "=== Installing GIMP and related packages ==="

# Update package manager
sudo apt-get update

# Install GIMP and common plugins/extensions
echo "Installing GIMP..."
sudo apt-get install -y \
    gimp \
    gimp-data-extras \
    gimp-plugin-registry \
    gimp-gmic \
    gimp-help-en \
    gimp-help-common

# Install additional graphics tools that work well with GIMP
echo "Installing additional graphics tools..."
sudo apt-get install -y \
    inkscape \
    imagemagick \
    graphicsmagick \
    exiftool \
    dcraw
# Install fonts for better text editing
echo "Installing additional fonts..."
sudo apt-get install -y \
    fonts-liberation \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-hack \
    fonts-firacode

# Install development tools (if users want to install additional plugins)
echo "Installing development tools for plugin compilation..."
sudo apt-get install -y \
    build-essential \
    libgimp2.0-dev \
    python3-pip \
    python3-dev

# Clean up package cache
# apt-get clean
# rm -rf /var/lib/apt/lists/*

echo "=== GIMP installation completed ==="
