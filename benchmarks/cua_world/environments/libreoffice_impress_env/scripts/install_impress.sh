#!/bin/bash
set -e

echo "=== Installing LibreOffice Impress and related packages ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install LibreOffice Impress and full suite
echo "Installing LibreOffice..."
apt-get install -y \
    libreoffice \
    libreoffice-impress \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-draw \
    libreoffice-base \
    libreoffice-math \
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

# Install pip packages (handle old pip that doesn't support --break-system-packages)
pip3 install --no-cache-dir \
    odfpy \
    python-pptx \
    pillow \
    lxml 2>/dev/null || \
pip3 install --no-cache-dir --break-system-packages \
    odfpy \
    python-pptx \
    pillow \
    lxml

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    scrot \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    imagemagick

# Install file handling utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    p7zip-full

# Install multimedia codecs for video/audio in presentations
echo "Installing multimedia support..."
apt-get install -y \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    ffmpeg

# Install fonts for better rendering
echo "Installing additional fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-liberation2 \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-noto-color-emoji \
    fonts-crosextra-carlito \
    fonts-crosextra-caladea \
    fonts-opensymbol

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== LibreOffice Impress installation completed ==="
