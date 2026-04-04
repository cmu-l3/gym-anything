#!/bin/bash
set -euo pipefail

echo "=== Installing FreeCAD ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -q

# Install FreeCAD and GUI automation tools
apt-get install -y \
    freecad \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    wget \
    curl \
    unzip \
    python3-lxml \
    python3-zipfile36 2>/dev/null || \
apt-get install -y \
    freecad \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    wget \
    curl \
    unzip \
    python3-lxml

echo "FreeCAD version: $(freecad --version 2>&1 | head -2 || echo 'unknown')"

# Create sample data directory (real FCStd files are provided via data/ mount in env.json)
mkdir -p /opt/freecad_samples

echo "=== FreeCAD installation complete ==="
