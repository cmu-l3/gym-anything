#!/bin/bash
set -e

echo "=== Installing Calligra Words ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Calligra Words and its dependencies
apt-get install -y \
    calligrawords \
    kde-runtime \
    breeze \
    breeze-icon-theme

# Install python-docx and odfpy for document generation and verification
apt-get install -y \
    python3-pip \
    python3-lxml

pip3 install python-docx odfpy

# Install GUI automation tools
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot

# Install fonts for proper rendering
apt-get install -y \
    fonts-liberation \
    fonts-dejavu-core \
    fonts-noto-core \
    fonts-freefont-ttf

echo "=== Calligra Words installation complete ==="
