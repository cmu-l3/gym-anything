#!/bin/bash
# install_firefox.sh - Pre-start hook for Firefox environment
# Installs Firefox and required dependencies
set -e

echo "=== Installing Firefox Environment ==="

# Non-interactive installation flags
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=l
export APT_LISTCHANGES_FRONTEND=none

# APT installation flags for reliability
APT_GET_INSTALL_FLAGS=(-yq --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# Update package lists
echo "Updating package lists..."
apt-get update -yq

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Install Firefox
echo "Installing Firefox..."
case "$ARCH" in
    x86_64|amd64)
        # Install Firefox from Mozilla PPA for latest stable release
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" software-properties-common
        add-apt-repository -y ppa:mozillateam/ppa

        # Pin Mozilla PPA Firefox over snap
        cat > /etc/apt/preferences.d/mozilla-firefox << 'EOF'
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF

        apt-get update -yq
        # Allow downgrades in case snap version is newer
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" --allow-downgrades firefox || \
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" firefox || \
        echo "Using existing Firefox installation"
        ;;
    aarch64|arm64)
        # For ARM64, use Firefox ESR or Chromium as fallback
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

# Install network and file utilities
echo "Installing utilities..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    curl \
    wget \
    jq \
    sqlite3 \
    netcat-openbsd \
    unzip

# Install Python and required libraries
echo "Installing Python tools..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    python3 \
    python3-pip \
    python3-dev \
    python3-pil

# Install Python packages for verification
pip3 install --break-system-packages \
    selenium \
    pillow \
    lz4 || true

# Install geckodriver for WebDriver support (optional but useful)
echo "Installing geckodriver..."
GECKO_VERSION="0.34.0"
case "$ARCH" in
    x86_64|amd64)
        GECKO_ARCH="linux64"
        ;;
    aarch64|arm64)
        GECKO_ARCH="linux-aarch64"
        ;;
    *)
        GECKO_ARCH="linux64"
        ;;
esac

wget -q "https://github.com/mozilla/geckodriver/releases/download/v${GECKO_VERSION}/geckodriver-v${GECKO_VERSION}-${GECKO_ARCH}.tar.gz" -O /tmp/geckodriver.tar.gz || true
if [ -f /tmp/geckodriver.tar.gz ]; then
    tar -xzf /tmp/geckodriver.tar.gz -C /usr/local/bin/
    chmod +x /usr/local/bin/geckodriver
    rm /tmp/geckodriver.tar.gz
    echo "geckodriver installed successfully"
else
    echo "WARNING: Could not download geckodriver, continuing without it"
fi

# Clean up
echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installation
echo "Verifying Firefox installation..."
if command -v firefox &> /dev/null; then
    FIREFOX_VERSION=$(firefox --version 2>/dev/null || echo "unknown")
    echo "Firefox installed: $FIREFOX_VERSION"
else
    echo "ERROR: Firefox installation failed!"
    exit 1
fi

echo "=== Firefox Environment Installation Complete ==="
