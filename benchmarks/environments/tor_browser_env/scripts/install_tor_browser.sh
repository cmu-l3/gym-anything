#!/bin/bash
# install_tor_browser.sh - Pre-start hook for Tor Browser environment
# Installs Tor Browser and required dependencies
set -e

echo "=== Installing Tor Browser Environment ==="

# Non-interactive installation flags
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=l
export APT_LISTCHANGES_FRONTEND=none

# APT installation flags for reliability
APT_GET_INSTALL_FLAGS=(-yq --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# Configure needrestart to never open an interactive UI (if present)
mkdir -p /etc/needrestart/conf.d
cat > /etc/needrestart/conf.d/99-noninteractive.conf <<'NEEDRESTART_EOF'
$nrconf{restart} = 'l';
$nrconf{ui} = 'stdio';
NEEDRESTART_EOF

# Update package lists
echo "Updating package lists..."
apt-get update -yq

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Install torbrowser-launcher from Ubuntu repository
# This is the recommended method as it handles downloads, verification, and updates
echo "Installing torbrowser-launcher..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" torbrowser-launcher

# Install GUI automation tools
echo "Installing GUI automation tools..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install network and file utilities
echo "Installing utilities..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    curl \
    wget \
    jq \
    sqlite3 \
    netcat-openbsd \
    unzip \
    gpg

# Install Python and required libraries
echo "Installing Python tools..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    python3 \
    python3-pip \
    python3-dev \
    python3-pil

# Install Python packages for verification
pip3 install --break-system-packages \
    pillow \
    lz4 || true

# Clean up
echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify torbrowser-launcher installation
echo "Verifying torbrowser-launcher installation..."
if command -v torbrowser-launcher &> /dev/null; then
    echo "torbrowser-launcher installed successfully"
else
    echo "ERROR: torbrowser-launcher installation failed!"
    exit 1
fi

echo "=== Tor Browser Environment Installation Complete ==="
