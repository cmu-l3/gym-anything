#!/bin/bash
set -e

echo "=== Installing Code_Saturne ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Code_Saturne and its dependencies
apt-get install -y \
    code-saturne \
    python3-pyqt5 \
    python3-pyqt5.qtwebengine \
    python3-matplotlib \
    python3-numpy \
    python3-scipy

# Install verification/testing tools
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    python3-pil \
    imagemagick \
    wget \
    git \
    curl

# Download real tutorial data from official Code_Saturne tutorials repository
echo "=== Downloading official Code_Saturne tutorial data ==="
TUTORIALS_DIR="/opt/code_saturne_tutorials"
mkdir -p "$TUTORIALS_DIR"

cd /tmp
git clone --depth 1 https://github.com/code-saturne/saturne-tutorials.git || {
    echo "WARNING: Git clone failed, trying wget fallback"
    mkdir -p saturne-tutorials
    cd saturne-tutorials
    # Download the Simple Junction tutorial mesh and data
    mkdir -p 01_Simple_Junction/MESH 01_Simple_Junction/case1/DATA
    wget -q "https://raw.githubusercontent.com/code-saturne/saturne-tutorials/master/01_Simple_Junction/MESH/downcomer.med" \
        -O 01_Simple_Junction/MESH/downcomer.med || echo "WARNING: Mesh download failed"
    wget -q "https://raw.githubusercontent.com/code-saturne/saturne-tutorials/master/01_Simple_Junction/case1/DATA/setup.xml" \
        -O 01_Simple_Junction/case1/DATA/setup.xml || echo "WARNING: setup.xml download failed"
    wget -q "https://raw.githubusercontent.com/code-saturne/saturne-tutorials/master/01_Simple_Junction/case1/DATA/run.cfg" \
        -O 01_Simple_Junction/case1/DATA/run.cfg || echo "WARNING: run.cfg download failed"
    cd /tmp
}

# Copy tutorial data to persistent location
if [ -d "/tmp/saturne-tutorials/01_Simple_Junction" ]; then
    cp -r /tmp/saturne-tutorials/01_Simple_Junction "$TUTORIALS_DIR/"
    echo "01_Simple_Junction tutorial copied successfully"
fi

if [ -d "/tmp/saturne-tutorials/05_Mixing_Tee" ]; then
    cp -r /tmp/saturne-tutorials/05_Mixing_Tee "$TUTORIALS_DIR/"
    echo "05_Mixing_Tee tutorial copied successfully"
fi

if [ -d "/tmp/saturne-tutorials/07_Heated_Square_Cavity" ]; then
    cp -r /tmp/saturne-tutorials/07_Heated_Square_Cavity "$TUTORIALS_DIR/"
    echo "07_Heated_Square_Cavity tutorial copied successfully"
fi

# Cleanup git clone
rm -rf /tmp/saturne-tutorials

# Set permissions
chmod -R 755 "$TUTORIALS_DIR"

# Verify code_saturne is installed
echo "=== Verifying Code_Saturne installation ==="
which code_saturne && echo "code_saturne binary found" || echo "WARNING: code_saturne not in PATH"
code_saturne info || echo "WARNING: code_saturne info failed"

echo "=== Code_Saturne installation complete ==="
