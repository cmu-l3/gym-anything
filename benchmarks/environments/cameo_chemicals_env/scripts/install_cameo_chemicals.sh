#!/bin/bash
# install_cameo_chemicals.sh - Pre-start hook for CAMEO Chemicals environment
# Installs Firefox and required dependencies for web-based chemical hazard lookup
set -e

echo "=== Installing CAMEO Chemicals Environment ==="

# Non-interactive installation flags
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=l
export APT_LISTCHANGES_FRONTEND=none

APT_GET_INSTALL_FLAGS=(-yq --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# Update package lists
echo "Updating package lists..."
apt-get update -yq

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Install Firefox from Mozilla PPA
echo "Installing Firefox..."
case "$ARCH" in
    x86_64|amd64)
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" software-properties-common
        add-apt-repository -y ppa:mozillateam/ppa

        # Pin Mozilla PPA Firefox over snap
        cat > /etc/apt/preferences.d/mozilla-firefox << 'EOF'
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF

        apt-get update -yq
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" --allow-downgrades firefox || \
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" firefox || \
        echo "Using existing Firefox installation"
        ;;
    aarch64|arm64)
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" --allow-downgrades firefox-esr || \
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" --allow-downgrades firefox || \
        echo "Using existing Firefox installation"
        ;;
    *)
        echo "WARNING: Unknown architecture $ARCH, attempting standard Firefox install"
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" --allow-downgrades firefox || \
        echo "Using existing Firefox installation"
        ;;
esac

# Install GUI automation tools
echo "Installing GUI automation tools..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install utilities
echo "Installing utilities..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    curl \
    wget \
    jq \
    python3 \
    python3-pip

# Clean up
echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify Firefox installation
echo "Verifying Firefox installation..."
if command -v firefox &> /dev/null; then
    FIREFOX_VERSION=$(firefox --version 2>/dev/null || echo "unknown")
    echo "Firefox installed: $FIREFOX_VERSION"
else
    echo "ERROR: Firefox installation failed!"
    exit 1
fi

echo "=== CAMEO Chemicals Environment Installation Complete ==="
