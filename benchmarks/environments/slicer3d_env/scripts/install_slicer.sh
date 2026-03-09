#!/bin/bash
# Don't use set -e since we want to handle errors gracefully
# This script must complete within ~300 seconds (SSH timeout)

echo "=== Installing 3D Slicer ==="
START_TIME=$(date +%s)

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update and install dependencies in parallel
echo "Installing dependencies..."
apt-get update -q &
APT_PID=$!

# Create installation directory while apt updates
SLICER_INSTALL_DIR="/opt/Slicer"
mkdir -p "$SLICER_INSTALL_DIR"
mkdir -p /home/ga/Documents/SlicerData/SampleData

# Wait for apt update
wait $APT_PID

# Install essential dependencies - run in two phases to ensure Qt libs get installed
echo "Installing Qt/X11 dependencies..."
apt-get install -y -q \
    libglu1-mesa \
    libpulse-mainloop-glib0 \
    libnss3 \
    libasound2 \
    libxcb-xinerama0 \
    libsm6 \
    libpcre2-16-0 \
    libxkbcommon0 \
    libdbus-1-3 \
    libxcb-cursor0 \
    libxcb-icccm4 \
    libxcb-keysyms1 \
    libxcb-shape0 \
    libxcb-render-util0 \
    libxcb-image0 || true

echo "Installing tools..."
apt-get install -y -q \
    wget \
    curl \
    scrot \
    wmctrl \
    xdotool \
    python3-pip \
    aria2 || apt-get install -y -q wget curl scrot wmctrl xdotool python3-pip

# Update shared library cache
ldconfig

# Verify critical dependencies are installed
if ! ldconfig -p | grep -q libxcb-xinerama; then
    echo "WARNING: libxcb-xinerama not found, trying to install..."
    apt-get install -y libxcb-xinerama0 || true
    ldconfig
fi
if ! ldconfig -p | grep -q libpcre2-16; then
    echo "WARNING: libpcre2-16 not found, trying to install..."
    apt-get install -y libpcre2-16-0 || true
    ldconfig
fi

echo "Installed Qt/X11 libraries:"
ldconfig -p | grep -E "(xinerama|pcre2|xcb-cursor)" || echo "Some libs may be missing"

# Calculate elapsed time
ELAPSED=$(($(date +%s) - START_TIME))
echo "Dependencies installed in ${ELAPSED}s"

# Download 3D Slicer using aria2 for speed (if available) or curl
# We have ~200 seconds left before SSH timeout
echo "Downloading 3D Slicer..."
cd /tmp

DOWNLOAD_URL="https://download.slicer.org/download?os=linux&stability=release"
DOWNLOAD_SUCCESS=false

# Try aria2 first (faster, supports parallel connections and resume)
if command -v aria2c &> /dev/null; then
    echo "Using aria2 for faster download..."
    if aria2c -x 4 -s 4 -k 1M --max-tries=2 --timeout=180 --connect-timeout=30 \
        -o slicer.tar.gz "$DOWNLOAD_URL" 2>/dev/null; then
        if [ -f slicer.tar.gz ] && [ $(stat -c%s slicer.tar.gz 2>/dev/null || echo 0) -gt 100000000 ]; then
            echo "aria2 download successful!"
            DOWNLOAD_SUCCESS=true
        fi
    fi
fi

# Fallback to curl with timeout
if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
    echo "Trying curl download..."
    # Use shorter timeout to avoid SSH timeout
    if curl -L -o slicer.tar.gz --connect-timeout 20 --max-time 180 \
        "$DOWNLOAD_URL" 2>/dev/null; then
        if [ -f slicer.tar.gz ] && [ $(stat -c%s slicer.tar.gz 2>/dev/null || echo 0) -gt 100000000 ]; then
            echo "curl download successful!"
            DOWNLOAD_SUCCESS=true
        fi
    fi
fi

# Final fallback: try direct kitware URL
if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
    echo "Trying kitware direct URL..."
    if curl -L -o slicer.tar.gz --connect-timeout 20 --max-time 180 \
        "https://slicer-packages.kitware.com/api/v1/item/65863a0a0a14a6f2b06afb63/download" 2>/dev/null; then
        if [ -f slicer.tar.gz ] && [ $(stat -c%s slicer.tar.gz 2>/dev/null || echo 0) -gt 100000000 ]; then
            echo "kitware download successful!"
            DOWNLOAD_SUCCESS=true
        fi
    fi
fi

ELAPSED=$(($(date +%s) - START_TIME))
echo "Download phase completed in ${ELAPSED}s"

if [ "$DOWNLOAD_SUCCESS" = "true" ]; then
    # Extract 3D Slicer
    echo "Extracting 3D Slicer..."
    tar -xzf slicer.tar.gz -C "$SLICER_INSTALL_DIR" --strip-components=1 &
    TAR_PID=$!

    # Clean up download file in background
    (sleep 5 && rm -f /tmp/slicer.tar.gz) &

    # Wait for extraction
    wait $TAR_PID

    # Create symlink for easy access
    ln -sf "$SLICER_INSTALL_DIR/Slicer" /usr/local/bin/Slicer
    ln -sf "$SLICER_INSTALL_DIR/Slicer" /usr/local/bin/slicer

    # Verify installation
    if [ -x "$SLICER_INSTALL_DIR/Slicer" ]; then
        echo "3D Slicer installed successfully at $SLICER_INSTALL_DIR"
    else
        echo "WARNING: 3D Slicer binary not executable"
    fi
else
    echo "WARNING: Could not download 3D Slicer within time limit."
    echo "The setup_slicer.sh script will attempt to complete installation."
    # Create marker file for setup script to retry
    touch /tmp/slicer_download_incomplete
fi

# Install Python dependencies (needed for verification and BraTS data generation)
echo "Installing Python dependencies..."
pip3 install -q pillow numpy nibabel scipy 2>/dev/null &

ELAPSED=$(($(date +%s) - START_TIME))
echo "=== 3D Slicer installation complete in ${ELAPSED}s ==="
