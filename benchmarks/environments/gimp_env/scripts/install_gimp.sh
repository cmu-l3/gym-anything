#!/bin/bash
set -euo pipefail

echo "=== Installing GIMP and related packages ==="

# Update package manager
apt-get update

# Install GIMP and common plugins/extensions
echo "Installing GIMP..."
apt-get install -y \
    gimp \
    gimp-data-extras \
    gimp-plugin-registry \
    gimp-gmic \
    gimp-help-en \
    gimp-help-common

# Install additional graphics tools that work well with GIMP
echo "Installing additional graphics tools..."
apt-get install -y \
    inkscape \
    imagemagick \
    graphicsmagick \
    exiftool \
    dcraw \
    ufraw-batch

# Install fonts for better text editing
echo "Installing additional fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-hack \
    fonts-firacode

# Install development tools (if users want to install additional plugins)
echo "Installing development tools for plugin compilation..."
apt-get install -y \
    build-essential \
    libgimp2.0-dev \
    python3-pip \
    python3-dev

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== GIMP installation completed ==="
