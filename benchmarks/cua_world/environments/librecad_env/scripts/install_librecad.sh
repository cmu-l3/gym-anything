#!/bin/bash
set -euo pipefail

echo "=== Installing LibreCAD and dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

echo "Installing LibreCAD..."
apt-get install -y librecad

echo "Installing UI automation and utility tools..."
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    wget \
    curl \
    poppler-utils

echo "Installing Python packages for DXF parsing (verification)..."
pip3 install ezdxf --break-system-packages 2>/dev/null || pip3 install ezdxf || true

echo "Creating sample DXF files directory..."
mkdir -p /opt/librecad_samples

echo "Downloading real-world DXF sample files..."

# Floor plan DXF from jscad sample-files (Apache-licensed open source project).
# This is a genuine architectural 2-car garage floor plan (~1.1MB) with multiple
# named layers, wall bracing notes, dimension annotations, and construction text.
# CRITICAL: This file is REQUIRED. If it fails to download or is too small,
# we abort immediately rather than silently falling back to synthetic data.
wget -O /opt/librecad_samples/floorplan.dxf \
    "https://raw.githubusercontent.com/jscad/sample-files/master/dxf/dxf-parser/floorplan.dxf"

FLOORPLAN_SIZE=$(stat -c%s /opt/librecad_samples/floorplan.dxf 2>/dev/null || echo 0)
if [ "$FLOORPLAN_SIZE" -lt 100000 ]; then
    echo "ERROR: floorplan.dxf is only ${FLOORPLAN_SIZE} bytes. Real file must be >100KB (~1.1MB)."
    echo "Download failed or file is truncated. Aborting — cannot use synthetic data for tasks."
    exit 1
fi
echo "floorplan.dxf downloaded successfully: ${FLOORPLAN_SIZE} bytes"

chmod -R 755 /opt/librecad_samples

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== LibreCAD installation complete ==="
