#!/bin/bash
set -e

echo "=== Installing GCompris Educational Software ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install UI automation and screenshot tools
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    x11-utils \
    python3-pip \
    python3-xlib \
    xvfb

# Install GCompris Qt (modern Qt-based version with 180+ activities)
# gcompris-qt is in Ubuntu universe repository
apt-get install -y gcompris-qt gcompris-qt-data

# Verify installation
# The binary is installed to /usr/games/gcompris-qt
if [ -x "/usr/games/gcompris-qt" ]; then
    echo "GCompris installed at /usr/games/gcompris-qt"
    # Create a symlink in /usr/local/bin for easy access
    ln -sf /usr/games/gcompris-qt /usr/local/bin/gcompris-qt
    echo "Created symlink at /usr/local/bin/gcompris-qt"
elif dpkg -l | grep -q gcompris-qt; then
    # Try to find it
    GCBIN=$(dpkg -L gcompris-qt 2>/dev/null | grep -E '/bin/|/games/' | head -1)
    if [ -n "$GCBIN" ] && [ -x "$GCBIN" ]; then
        ln -sf "$GCBIN" /usr/local/bin/gcompris-qt
        echo "Created symlink from $GCBIN to /usr/local/bin/gcompris-qt"
    else
        echo "WARNING: Could not locate gcompris-qt binary"
    fi
else
    echo "FATAL: GCompris installation failed"
    exit 1
fi

echo "GCompris version: $(/usr/games/gcompris-qt --version 2>/dev/null || echo 'unknown')"

echo "=== GCompris installation complete ==="
