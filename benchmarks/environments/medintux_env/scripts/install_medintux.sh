#!/bin/bash
set -euo pipefail

echo "=== Installing MedinTux and dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

echo "Installing GUI automation and utility tools..."
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    wget \
    curl \
    p7zip-full \
    xterm

echo "Installing MySQL server..."
apt-get install -y mysql-server

echo "Installing Wine for running MedinTux Windows application..."
# MedinTux Windows installer is 32-bit (PE32), so we MUST have wine32
# Enable i386 multiarch first, then install wine64 + wine32
dpkg --add-architecture i386
apt-get update

# Install wine with 32-bit support
apt-get install -y wine wine64 2>/dev/null || true
apt-get install -y wine32:i386 2>/dev/null || \
    apt-get install -y wine32 2>/dev/null || true

echo "Wine version: $(wine --version 2>/dev/null || echo 'not found')"
echo "Wine32 check: $(dpkg -l wine32 2>/dev/null | tail -1 || echo 'not installed')"

echo "Installing Python packages for task utilities..."
pip3 install pymysql --break-system-packages 2>/dev/null || pip3 install pymysql || true

echo "Creating MedinTux installation directory..."
mkdir -p /opt/medintux
mkdir -p /home/ga/MedinTux

echo "Downloading MedinTux Windows installer from SourceForge..."
# MedinTux 2.16.012 Windows installer - last official release (2014-07-11, 210.9 MB)
# SHA1: 417e0e4fe2bafb0c321c55fd6d3494e8a40d6ce3
wget -O /opt/medintux/medintux-2.16.012.exe \
    "https://downloads.sourceforge.net/project/medintux/Windows/2.16.012/medintux-2.16.012.exe" \
    --progress=dot:mega \
    --tries=3 \
    --timeout=600

INSTALLER_SIZE=$(stat -c%s /opt/medintux/medintux-2.16.012.exe 2>/dev/null || echo 0)
echo "MedinTux installer downloaded: ${INSTALLER_SIZE} bytes"

if [ "$INSTALLER_SIZE" -lt 100000000 ]; then
    echo "ERROR: Installer is only ${INSTALLER_SIZE} bytes — expected ~210MB."
    echo "Download failed or file is truncated."
    exit 1
fi

echo "MedinTux installer verified: ${INSTALLER_SIZE} bytes"

echo "Downloading MedinTux demo SQL database (DrTuxTest)..."
# The demo database SQL is distributed separately from the installer
# This is the official demo database from medintux.org with sample patients and data
wget -O /opt/medintux/DrTuxTest_demo.sql \
    "https://medintux.org/download/DrTuxTest_demo.sql" \
    --tries=3 \
    --timeout=60 2>/dev/null || true

# If the official download fails, we'll use data creation in setup script
DEMO_SQL_SIZE=$(stat -c%s /opt/medintux/DrTuxTest_demo.sql 2>/dev/null || echo 0)
echo "Demo SQL file size: ${DEMO_SQL_SIZE} bytes"

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== MedinTux installation preparation complete ==="
