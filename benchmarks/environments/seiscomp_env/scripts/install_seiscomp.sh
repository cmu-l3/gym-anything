#!/bin/bash
set -e

echo "=== Installing SeisComP ==="

export DEBIAN_FRONTEND=noninteractive

# ─── 1. Install system dependencies ──────────────────────────────────────────

echo "--- Installing system dependencies ---"
apt-get update

apt-get install -y \
    python3-dev python3-pip python3-numpy python3-setuptools \
    qtbase5-dev libqt5svg5-dev libqt5opengl5-dev qt5-qmake \
    libssl-dev libxml2-dev libmariadb-dev libpq-dev libsqlite3-dev \
    mariadb-server mariadb-client \
    wget curl jq unzip \
    xdotool wmctrl scrot x11-utils xclip imagemagick \
    python3-pil python3-lxml \
    libncurses-dev libboost-all-dev

echo "Dependencies installed"

# ─── 2. Install SeisComP from pre-built binary package ───────────────────────

echo "--- Installing SeisComP from binary package ---"

SEISCOMP_PREFIX=/home/ga/seiscomp
SEISCOMP_VERSION="7.1.2"
PACKAGE_URL="https://data.gempa.de/packages/Public/seiscomp/7/ubuntu/22.04/x86_64/seiscomp-${SEISCOMP_VERSION}-ubuntu-22.04-x86_64.tar.gz"

echo "Downloading SeisComP ${SEISCOMP_VERSION}..."
wget --timeout=300 "$PACKAGE_URL" -O /tmp/seiscomp.tar.gz

echo "Extracting to ${SEISCOMP_PREFIX}..."
mkdir -p /home/ga
tar xzf /tmp/seiscomp.tar.gz -C /home/ga/
rm -f /tmp/seiscomp.tar.gz

echo "SeisComP extracted"

# ─── 3. Set ownership and environment ────────────────────────────────────────

chown -R ga:ga "$SEISCOMP_PREFIX"

cat >> /home/ga/.bashrc << 'ENVEOF'

# SeisComP environment
export SEISCOMP_ROOT=/home/ga/seiscomp
export PATH=/home/ga/seiscomp/bin:$PATH
export LD_LIBRARY_PATH=/home/ga/seiscomp/lib:$LD_LIBRARY_PATH
export PYTHONPATH=/home/ga/seiscomp/lib/python:$PYTHONPATH
export MANPATH=/home/ga/seiscomp/share/man:$MANPATH
ENVEOF

chown ga:ga /home/ga/.bashrc

# ─── 4. Cleanup ──────────────────────────────────────────────────────────────

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== SeisComP binary installation complete ==="

# Verify key binaries exist
for BIN in seiscomp scolv scconfig scrttv scmv scmaster; do
    if [ -x "$SEISCOMP_PREFIX/bin/$BIN" ]; then
        echo "  OK: $BIN found"
    else
        echo "  WARN: $BIN not found"
    fi
done
