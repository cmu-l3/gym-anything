#!/bin/bash
# set -euo pipefail

echo "=== Installing GeoGebra and related packages ==="

# Update package manager
apt-get update

# Install GeoGebra Classic 6 from official repository
echo "Adding GeoGebra repository..."
apt-get install -y wget gnupg2

# Add GeoGebra repository and key
wget -qO- https://www.geogebra.net/linux/apt/geogebra.gpg.key | gpg --dearmor -o /usr/share/keyrings/geogebra-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/geogebra-archive-keyring.gpg] https://www.geogebra.net/linux/ stable main" | tee /etc/apt/sources.list.d/geogebra.list

apt-get update

# Install GeoGebra Classic 6
echo "Installing GeoGebra Classic 6..."
apt-get install -y geogebra-classic || {
    echo "GeoGebra Classic 6 not available, trying GeoGebra 5..."
    apt-get install -y geogebra || {
        echo "Trying flatpak installation..."
        apt-get install -y flatpak
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        flatpak install -y flathub org.geogebra.GeoGebra
    }
}

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install Python libraries for verification
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-dev

pip3 install --no-cache-dir \
    pillow \
    lxml \
    numpy

# Install file utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    curl \
    wget

# Install fonts for better math rendering
echo "Installing fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-freefont-ttf \
    fonts-lmodern \
    fonts-texgyre

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== GeoGebra installation completed ==="
