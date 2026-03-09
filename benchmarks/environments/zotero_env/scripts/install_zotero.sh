#!/bin/bash
set -e

echo "=== Installing Zotero ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install dependencies
apt-get install -y \
    wget \
    tar \
    xdotool \
    wmctrl \
    scrot \
    imagemagick \
    python3-pip \
    python3-venv \
    jq \
    sqlite3 \
    curl \
    ca-certificates

# Download Zotero tarball (latest 7.x version)
ZOTERO_VERSION="7.0.11"
ZOTERO_URL="https://www.zotero.org/download/client/dl?channel=release&platform=linux-x86_64&version=${ZOTERO_VERSION}"

echo "Downloading Zotero ${ZOTERO_VERSION}..."
cd /tmp
wget -O zotero.tar.bz2 "$ZOTERO_URL"

# Extract to /opt
echo "Extracting Zotero to /opt..."
tar -xjf zotero.tar.bz2 -C /opt/

# Rename directory to zotero (it extracts as Zotero_linux-x86_64)
if [ -d /opt/Zotero_linux-x86_64 ]; then
    mv /opt/Zotero_linux-x86_64 /opt/zotero
fi

# Run set_launcher_icon script to update .desktop file
cd /opt/zotero
./set_launcher_icon

# Install desktop file
cp /opt/zotero/zotero.desktop /usr/share/applications/
chmod +x /usr/share/applications/zotero.desktop

# Create symlink for easier access
ln -sf /opt/zotero/zotero /usr/local/bin/zotero

# Cleanup
rm -f /tmp/zotero.tar.bz2

# Verify installation
which zotero && echo "Zotero binary linked at: $(which zotero)"

echo "=== Zotero installation complete ==="
