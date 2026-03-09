#!/bin/bash
# set -euo pipefail

echo "=== Installing LibreOffice Writer and related packages ==="

# Update package manager
apt-get update

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Install LibreOffice full suite
echo "Installing LibreOffice..."
apt-get install -y \
    libreoffice \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-base \
    libreoffice-help-en-us \
    libreoffice-l10n-en-us \
    libreoffice-java-common

# Install Python UNO bridge for programmatic access
echo "Installing Python UNO bridge..."
apt-get install -y \
    python3-uno \
    libreoffice-script-provider-python

# Install file format parsing libraries
echo "Installing file parsing libraries..."
apt-get install -y \
    python3-pip \
    python3-dev \
    python3-lxml

pip3 install --no-cache-dir --break-system-packages \
    python-docx \
    odfpy \
    lxml 2>/dev/null || \
pip3 install --no-cache-dir \
    python-docx \
    odfpy \
    lxml || true

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip

# Install file handling utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    p7zip-full

# Install fonts for better rendering
echo "Installing additional fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-liberation2 \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-crosextra-carlito \
    fonts-crosextra-caladea \
    fonts-opensymbol

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== LibreOffice Writer installation completed ==="
