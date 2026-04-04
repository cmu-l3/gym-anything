#!/bin/bash
# set -euo pipefail

echo "=== Installing VLC Media Player and related packages ==="

# Update package manager
apt-get update

# Install VLC and plugins
echo "Installing VLC..."
apt-get install -y \
    vlc \
    vlc-plugin-base \
    vlc-plugin-video-output \
    vlc-plugin-notify \
    vlc-plugin-samba \
    vlc-plugin-fluidsynth \
    vlc-plugin-jack \
    vlc-plugin-svg
# Install media analysis tools
echo "Installing media analysis tools..."
apt-get install -y \
    ffmpeg \
    mediainfo \
    mediainfo-gui \
    libimage-exiftool-perl

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip

# Install network tools for VLC RC interface
echo "Installing network tools..."
apt-get install -y \
    netcat-openbsd \
    socat

# Install Python libraries for verification
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-dev

pip3 install --no-cache-dir \
    pillow \
    opencv-python-headless \
    pymediainfo \
    mutagen

# Install file utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    p7zip-full \
    curl \
    wget

# Install subtitle tools
echo "Installing subtitle tools..."
apt-get install -y \
    subtitleeditor \
    gaupol

# Install fonts for subtitle rendering
echo "Installing fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-freefont-ttf

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== VLC Media Player installation completed ==="
