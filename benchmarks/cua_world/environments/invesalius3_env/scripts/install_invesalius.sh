#!/bin/bash
set -e

echo "=== Installing InVesalius 3 ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Base tools and GUI automation
apt-get install -y \
    ca-certificates \
    curl \
    wget \
    unzip \
    gnupg \
    xdotool \
    wmctrl \
    x11-utils \
    x11-xserver-utils \
    scrot \
    python3-pip

# Try distro packages first
INVE_INSTALLED=false
if apt-get install -y invesalius; then
    INVE_INSTALLED=true
else
    echo "apt package 'invesalius' not available."
fi

if [ "$INVE_INSTALLED" = "false" ]; then
    if apt-get install -y invesalius3; then
        INVE_INSTALLED=true
    else
        echo "apt package 'invesalius3' not available."
    fi
fi

# Fallback to Flatpak (officially supported for other distros)
if [ "$INVE_INSTALLED" = "false" ]; then
    echo "Falling back to Flatpak install for InVesalius."
    apt-get install -y flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub br.gov.cti.invesalius
fi

# Optional DICOM tooling
apt-get install -y dcmtk || true

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== InVesalius installation complete ==="
