#!/bin/bash
# install_edge.sh - Pre-start hook for Microsoft Edge environment
# Installs Microsoft Edge and required dependencies
set -e

echo "=== Installing Microsoft Edge Environment ==="

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

# Install prerequisites
echo "Installing prerequisites..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    curl \
    wget \
    gnupg

# Add Microsoft GPG key
echo "Adding Microsoft GPG key..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-edge.gpg

# Add Microsoft Edge repository
echo "Adding Microsoft Edge repository..."
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list

# Update package lists with new repository
echo "Updating package lists..."
apt-get update -yq

# Install Microsoft Edge Stable
echo "Installing Microsoft Edge Stable..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" microsoft-edge-stable || {
    echo "Failed to install Edge, trying alternative method..."
    # Alternative: Download and install directly
    wget -q "https://packages.microsoft.com/repos/edge/pool/main/m/microsoft-edge-stable/microsoft-edge-stable_131.0.2903.99-1_amd64.deb" -O /tmp/edge.deb || \
    wget -q "https://go.microsoft.com/fwlink?linkid=2149051" -O /tmp/edge.deb
    dpkg -i /tmp/edge.deb || apt-get install -f -y
    rm -f /tmp/edge.deb
}

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
    pillow || true

# Install msedgedriver for WebDriver support (optional)
echo "Installing msedgedriver..."
EDGE_VERSION=$(microsoft-edge --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
if [ -n "$EDGE_VERSION" ]; then
    EDGE_MAJOR=$(echo "$EDGE_VERSION" | cut -d. -f1)
    # Try to download matching driver
    wget -q "https://msedgedriver.azureedge.net/${EDGE_VERSION}/edgedriver_linux64.zip" -O /tmp/edgedriver.zip 2>/dev/null || \
    wget -q "https://msedgedriver.azureedge.net/LATEST_RELEASE_${EDGE_MAJOR}" -O /tmp/driver_version.txt 2>/dev/null

    if [ -f /tmp/edgedriver.zip ]; then
        unzip -o /tmp/edgedriver.zip -d /usr/local/bin/
        chmod +x /usr/local/bin/msedgedriver 2>/dev/null || true
        rm /tmp/edgedriver.zip
        echo "msedgedriver installed successfully"
    else
        echo "WARNING: Could not download msedgedriver, continuing without it"
    fi
else
    echo "WARNING: Could not determine Edge version for driver download"
fi

# Clean up
echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installation
echo "Verifying Microsoft Edge installation..."
if command -v microsoft-edge &> /dev/null; then
    EDGE_VERSION=$(microsoft-edge --version 2>/dev/null || echo "unknown")
    echo "Microsoft Edge installed: $EDGE_VERSION"
else
    echo "ERROR: Microsoft Edge installation failed!"
    exit 1
fi

echo "=== Microsoft Edge Environment Installation Complete ==="
