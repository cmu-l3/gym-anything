#!/bin/bash
set -euo pipefail

echo "=== Installing NASA GMAT (General Mission Analysis Tool) ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install system dependencies
apt-get install -y \
    wget curl unzip \
    libgl1-mesa-glx libgl1-mesa-dri libopengl0 libglu1-mesa \
    libx11-6 libxext6 libxrender1 libxrandr2 libxi6 libxfixes3 \
    libgtk-3-0 libpango-1.0-0 libcairo2 libatk1.0-0 libgdk-pixbuf-2.0-0 \
    libfontconfig1 libfreetype6 \
    xdotool wmctrl scrot imagemagick x11-utils xclip \
    python3-pip python3-dev \
    fonts-liberation fonts-dejavu-extra

echo "=== Downloading GMAT R2022a ==="

GMAT_DIR="/opt/GMAT"
mkdir -p "$GMAT_DIR"
cd /tmp

# Try R2022a first, with fallbacks
GMAT_DOWNLOADED=false

# Attempt 1: R2022a from SourceForge
if [ "$GMAT_DOWNLOADED" = "false" ]; then
    echo "Trying GMAT R2022a from SourceForge..."
    if wget -q --timeout=120 --tries=3 \
        "https://sourceforge.net/projects/gmat/files/GMAT/GMAT-R2022a/gmat-ubuntu-x64-R2022a.tar.gz/download" \
        -O gmat-ubuntu.tar.gz 2>/dev/null; then
        if [ -s gmat-ubuntu.tar.gz ] && file gmat-ubuntu.tar.gz | grep -q "gzip"; then
            echo "Downloaded R2022a successfully"
            GMAT_DOWNLOADED=true
        else
            echo "R2022a download invalid, trying next..."
            rm -f gmat-ubuntu.tar.gz
        fi
    else
        echo "R2022a download failed, trying next..."
        rm -f gmat-ubuntu.tar.gz
    fi
fi

# Attempt 2: R2020a from SourceForge
if [ "$GMAT_DOWNLOADED" = "false" ]; then
    echo "Trying GMAT R2020a from SourceForge..."
    if wget -q --timeout=120 --tries=3 \
        "https://sourceforge.net/projects/gmat/files/GMAT/GMAT-R2020a/gmat-ubuntu-x64-R2020a.tar.gz/download" \
        -O gmat-ubuntu.tar.gz 2>/dev/null; then
        if [ -s gmat-ubuntu.tar.gz ] && file gmat-ubuntu.tar.gz | grep -q "gzip"; then
            echo "Downloaded R2020a successfully"
            GMAT_DOWNLOADED=true
        else
            echo "R2020a download invalid, trying next..."
            rm -f gmat-ubuntu.tar.gz
        fi
    else
        echo "R2020a download failed, trying next..."
        rm -f gmat-ubuntu.tar.gz
    fi
fi

# Attempt 3: R2025a from SourceForge
if [ "$GMAT_DOWNLOADED" = "false" ]; then
    echo "Trying GMAT R2025a from SourceForge..."
    if wget -q --timeout=120 --tries=3 \
        "https://sourceforge.net/projects/gmat/files/GMAT/GMAT-R2025a/gmat-ubuntu-x64-R2025a.tar.gz/download" \
        -O gmat-ubuntu.tar.gz 2>/dev/null; then
        if [ -s gmat-ubuntu.tar.gz ] && file gmat-ubuntu.tar.gz | grep -q "gzip"; then
            echo "Downloaded R2025a successfully"
            GMAT_DOWNLOADED=true
        else
            echo "R2025a download invalid"
            rm -f gmat-ubuntu.tar.gz
        fi
    else
        echo "R2025a download failed"
        rm -f gmat-ubuntu.tar.gz
    fi
fi

if [ "$GMAT_DOWNLOADED" = "false" ]; then
    echo "ERROR: Failed to download GMAT from any source"
    exit 1
fi

echo "=== Extracting GMAT ==="

# Extract to a temp location first to find the actual directory
mkdir -p /tmp/gmat_extract
tar -xzf gmat-ubuntu.tar.gz -C /tmp/gmat_extract

# The tarball typically extracts to GMAT/R2022a/ or similar versioned structure
# Find the bin directory that contains the GMAT binary
GMAT_BIN_DIR=$(find /tmp/gmat_extract -name "GMAT-R*" -o -name "GMAT_Beta" -o -name "GmatConsole" 2>/dev/null | head -1)
if [ -n "$GMAT_BIN_DIR" ]; then
    GMAT_ACTUAL_ROOT=$(dirname "$(dirname "$GMAT_BIN_DIR")")
    echo "Found GMAT root at: $GMAT_ACTUAL_ROOT"
else
    # Fallback: find any directory with a bin/ subdirectory containing executables
    GMAT_ACTUAL_ROOT=$(find /tmp/gmat_extract -name "bin" -type d -exec test -e {}/GmatConsole -o -e {}/GMAT_Beta \; -print 2>/dev/null | head -1 | xargs dirname)
    if [ -z "$GMAT_ACTUAL_ROOT" ]; then
        # Last resort: use the deepest GMAT directory
        GMAT_ACTUAL_ROOT=$(find /tmp/gmat_extract -maxdepth 3 -name "bin" -type d 2>/dev/null | head -1 | xargs dirname)
    fi
fi

if [ -z "$GMAT_ACTUAL_ROOT" ] || [ ! -d "$GMAT_ACTUAL_ROOT/bin" ]; then
    echo "ERROR: Could not find GMAT directory structure after extraction"
    find /tmp/gmat_extract -maxdepth 4 -type d
    exit 1
fi

# Move the actual GMAT root to /opt/GMAT (removing any nesting)
rm -rf /opt/GMAT
mv "$GMAT_ACTUAL_ROOT" /opt/GMAT

echo "=== GMAT extracted to /opt/GMAT ==="
ls -la /opt/GMAT/
ls -la /opt/GMAT/bin/ | head -10

# Find and verify the GUI binary
GMAT_BIN=""
for candidate in /opt/GMAT/bin/GMAT_Beta /opt/GMAT/bin/GMAT-R2022a /opt/GMAT/bin/GMAT-R2020a /opt/GMAT/bin/GMAT-R2025a; do
    if [ -f "$candidate" ] && file "$candidate" | grep -q "ELF"; then
        GMAT_BIN="$candidate"
        echo "Found GMAT GUI binary: $GMAT_BIN"
        break
    fi
done

# Also find console binary
GMAT_CONSOLE=""
for candidate in /opt/GMAT/bin/GmatConsole /opt/GMAT/bin/GmatConsole-R2022a /opt/GMAT/bin/GmatConsole-R2020a /opt/GMAT/bin/GmatConsole-R2025a; do
    if [ -f "$candidate" ]; then
        GMAT_CONSOLE="$candidate"
        echo "Found GMAT Console binary: $GMAT_CONSOLE"
        break
    fi
done

if [ -z "$GMAT_BIN" ]; then
    echo "WARNING: Could not find GMAT GUI binary"
    find /opt/GMAT/bin -maxdepth 1 -type f -executable 2>/dev/null || true
fi

# Set permissions
chmod -R a+rx /opt/GMAT/
chown -R ga:ga /opt/GMAT/

# Clean up
rm -f /tmp/gmat-ubuntu.tar.gz
rm -rf /tmp/gmat_extract

# List sample scripts (real NASA mission data)
echo "=== Sample Missions (Real Data) ==="
if [ -d "/opt/GMAT/samples" ]; then
    ls /opt/GMAT/samples/
    echo "Found $(find /opt/GMAT/samples -name '*.script' | wc -l) sample .script files"
fi

# Install python dependencies for verification
pip3 install lxml 2>/dev/null || true

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== GMAT installation complete ==="
