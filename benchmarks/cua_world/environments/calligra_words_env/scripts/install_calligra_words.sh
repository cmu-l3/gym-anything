#!/bin/bash
set -e

echo "=== Installing Calligra Words ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Calligra Words, document libraries, and automation tools
apt-get install -y \
    calligrawords \
    breeze \
    breeze-icon-theme \
    dbus-x11

apt-get install -y \
    python3-docx \
    python3-lxml \
    python3-odf

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

command -v calligrawords >/dev/null

echo "=== Calligra Words installation complete ==="
