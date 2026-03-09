#!/bin/bash
set -euo pipefail

echo "=== Installing Jolly Lobby Track and dependencies ==="

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
    cabextract \
    p7zip-full \
    xterm \
    unzip

echo "Installing Wine for running Lobby Track Windows application..."
# Lobby Track is a 32-bit .NET Windows application
# Enable i386 multiarch, then install wine64 + wine32
dpkg --add-architecture i386
apt-get update

# Install wine with 32-bit support
apt-get install -y wine wine64 2>/dev/null || true
apt-get install -y wine32:i386 2>/dev/null || \
    apt-get install -y wine32 2>/dev/null || true

echo "Wine version: $(wine --version 2>/dev/null || echo 'not found')"

echo "Creating Lobby Track installation directory..."
mkdir -p /opt/lobbytrack
mkdir -p /home/ga/LobbyTrack

echo "Downloading Jolly Lobby Track Free installer..."
# Lobby Track Free from Jolly Technologies (original URL now 404, using Wayback Machine)
# Original URL: http://www.jollytech.com/download/LobbyTrackFreeSetup.exe
# Source: Official Jolly Technologies distribution, archived by Wayback Machine
# File: LobbyTrackFreeSetup.exe (~50.8 MB, version ~4.1/6.7)
WAYBACK_URL="https://web.archive.org/web/20170809181430/http://jollytech.com/download/LobbyTrackFreeSetup.exe"

wget -O /opt/lobbytrack/LobbyTrackFreeSetup.exe \
    "$WAYBACK_URL" \
    --progress=dot:mega \
    --tries=3 \
    --timeout=600

INSTALLER_SIZE=$(stat -c%s /opt/lobbytrack/LobbyTrackFreeSetup.exe 2>/dev/null || echo 0)
echo "Lobby Track installer downloaded: ${INSTALLER_SIZE} bytes"

if [ "$INSTALLER_SIZE" -lt 5000000 ]; then
    echo "ERROR: Installer download failed (${INSTALLER_SIZE} bytes, expected ~50MB)."
    exit 1
fi

echo "Extracting Lobby Track installer with 7z..."
# The InstallShield installer bundles .NET prerequisite and Lobby Track files.
# We extract with 7z to avoid running the full InstallShield wizard,
# which tries to install .NET 4.5.2 (broken in Wine 6.0.3).
mkdir -p /opt/lobbytrack/extracted
7z x /opt/lobbytrack/LobbyTrackFreeSetup.exe -o/opt/lobbytrack/extracted -y > /tmp/lt_extract.log 2>&1 || true
echo "Extraction complete. Contents:"
find /opt/lobbytrack/extracted -maxdepth 3 -type f | head -40

echo "Copying realistic visitor data to VM..."
cp -r /workspace/data /opt/lobbytrack/data 2>/dev/null || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Jolly Lobby Track installation preparation complete ==="
