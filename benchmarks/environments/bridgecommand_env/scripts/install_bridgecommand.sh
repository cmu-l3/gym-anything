#!/bin/bash
set -e

echo "=== Installing Bridge Command ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install build dependencies and runtime libraries
echo "Installing dependencies..."
apt-get install -y \
    wget \
    curl \
    git \
    scrot \
    wmctrl \
    xdotool \
    x11-utils \
    python3-pip \
    cmake \
    build-essential \
    mesa-common-dev \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    libegl1-mesa \
    libgbm1 \
    mesa-utils \
    libglu1-mesa \
    libxxf86vm-dev \
    freeglut3-dev \
    libxext-dev \
    libxcursor-dev \
    portaudio19-dev \
    libsndfile1-dev \
    libopenxr-dev

# Build Bridge Command from source
# The .deb package requires Ubuntu 24.04+ (libc6 >= 2.38), so we build from source
echo "Building Bridge Command from source..."
cd /tmp
if [ -d /tmp/bc ]; then
    rm -rf /tmp/bc
fi

git clone --depth 1 https://github.com/bridgecommand/bc.git
cd /tmp/bc/bin

echo "Running cmake..."
cmake ../src

echo "Compiling (this may take several minutes)..."
make -j$(nproc)

# Verify the build produced the binary
if [ ! -x /tmp/bc/bin/bridgecommand ]; then
    echo "ERROR: Build failed - bridgecommand binary not found"
    ls -la /tmp/bc/bin/
    exit 1
fi

echo "Build successful"

# Install to /opt/bridgecommand (includes binary + all data files)
echo "Installing to /opt/bridgecommand..."
mkdir -p /opt/bridgecommand
cp -r /tmp/bc/bin/* /opt/bridgecommand/

# Create symlink
ln -sf /opt/bridgecommand/bridgecommand /usr/local/bin/bridgecommand

# Verify installation
echo "Verifying installation..."
ls -la /opt/bridgecommand/bridgecommand
echo "Scenarios:"
ls /opt/bridgecommand/Scenarios/ 2>/dev/null || echo "No Scenarios directory found"
echo "Models:"
ls /opt/bridgecommand/Models/ 2>/dev/null | head -10 || echo "No Models directory found"
echo "World:"
ls /opt/bridgecommand/World/ 2>/dev/null | head -10 || echo "No World directory found"

# Save data directory path
echo "/opt/bridgecommand" > /tmp/bc_data_dir.txt
echo "/opt/bridgecommand/bridgecommand" > /tmp/bc_bin_path.txt

# Clean up build artifacts (but keep the installation)
rm -rf /tmp/bc

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Bridge Command installation complete ==="
echo "Binary: /opt/bridgecommand/bridgecommand"
echo "Data: /opt/bridgecommand"
