#!/bin/bash
set -e

echo "=== Installing Stellarium ==="

export DEBIAN_FRONTEND=noninteractive

# ── 1. System utilities ──────────────────────────────────────────────
apt-get update
apt-get install -y \
    software-properties-common \
    scrot wmctrl xdotool imagemagick \
    python3-pip python3-pil \
    wget curl unzip jq

# ── 2. Install Mesa/OpenGL libraries for software rendering ─────────
# Stellarium requires OpenGL. In QEMU VMs without GPU, we use Mesa's
# llvmpipe software renderer. Install comprehensive Mesa packages.
apt-get install -y \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    mesa-utils \
    libglu1-mesa \
    libosmesa6 \
    libegl1-mesa 2>/dev/null || true

# ── 3. Set software rendering globally ──────────────────────────────
# Ensures all processes use llvmpipe for OpenGL
echo 'LIBGL_ALWAYS_SOFTWARE=1' >> /etc/environment
echo 'export LIBGL_ALWAYS_SOFTWARE=1' >> /etc/profile.d/mesa-software.sh

# ── 4. Install Stellarium from universe repo ────────────────────────
# Ubuntu 22.04 provides Stellarium 0.20.4 (Qt5-based) which works
# reliably with llvmpipe software rendering.
echo "--- Installing Stellarium from universe repo ---"
apt-get install -y stellarium

# Verify binary exists
if ! command -v stellarium &>/dev/null; then
    echo "ERROR: stellarium binary not found after install"
    exit 1
fi

echo "Stellarium installed: $(which stellarium)"

# ── 5. Install Python dependencies for data processing ──────────────
pip3 install astropy 2>/dev/null || true

echo "=== Stellarium installation complete ==="
