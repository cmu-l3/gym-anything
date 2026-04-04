#!/bin/bash
# set -euo pipefail

echo "=== Installing QGIS and related packages ==="

# Update package manager
apt-get update

# Install required dependencies first
echo "Installing dependencies..."
apt-get install -y \
    gnupg \
    software-properties-common \
    wget \
    curl \
    ca-certificates

# Add QGIS signing key
echo "Adding QGIS repository key..."
mkdir -m755 -p /etc/apt/keyrings
wget -O /etc/apt/keyrings/qgis-archive-keyring.gpg https://download.qgis.org/downloads/qgis-archive-keyring.gpg

# Detect Ubuntu version
UBUNTU_CODENAME=$(lsb_release -cs)
echo "Detected Ubuntu codename: $UBUNTU_CODENAME"

# Add QGIS repository (LTR version for stability)
echo "Adding QGIS LTR repository..."
cat > /etc/apt/sources.list.d/qgis.sources << EOF
Types: deb deb-src
URIs: https://qgis.org/ubuntu-ltr
Suites: ${UBUNTU_CODENAME}
Architectures: amd64
Components: main
Signed-By: /etc/apt/keyrings/qgis-archive-keyring.gpg
EOF

# Update package lists with new repository
apt-get update

# Install QGIS
echo "Installing QGIS..."
apt-get install -y qgis qgis-plugin-grass || {
    echo "QGIS LTR installation failed, trying default Ubuntu package..."
    # Fallback to default Ubuntu package if QGIS repo fails
    rm -f /etc/apt/sources.list.d/qgis.sources
    apt-get update
    apt-get install -y qgis
}

# Install additional QGIS plugins and tools
echo "Installing QGIS additional tools..."
apt-get install -y \
    qgis-plugin-grass \
    grass \
    gdal-bin \
    python3-gdal \
    libgdal-dev || true

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install Python libraries for verification and GIS
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-dev

pip3 install --no-cache-dir \
    pillow \
    pyproj \
    shapely \
    geopandas \
    fiona || true

# Install file utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    p7zip-full

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== QGIS installation completed ==="

# Verify installation
if command -v qgis &> /dev/null; then
    echo "QGIS version: $(qgis --version 2>&1 | head -1)"
else
    echo "Warning: QGIS command not found in PATH"
fi
