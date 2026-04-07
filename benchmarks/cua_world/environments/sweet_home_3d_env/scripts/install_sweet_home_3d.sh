#!/bin/bash
# Do NOT use set -e: allow graceful error handling

echo "=== Installing Sweet Home 3D ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update -y || true

# Install system dependencies for GUI automation and general utilities
apt-get install -y --no-install-recommends \
    xdotool wmctrl scrot \
    wget curl unzip \
    imagemagick \
    libxrender1 libxtst6 libxi6 libxrandr2 || {
    echo "WARNING: Some packages may have failed to install"
}

# Download Sweet Home 3D Linux 64-bit tarball (bundles its own JRE)
SH3D_VERSION="7.5"
SH3D_TARBALL="SweetHome3D-${SH3D_VERSION}-linux-x64.tgz"
SH3D_URL="https://sourceforge.net/projects/sweethome3d/files/SweetHome3D/SweetHome3D-${SH3D_VERSION}/${SH3D_TARBALL}/download"

echo "Downloading Sweet Home 3D ${SH3D_VERSION}..."
cd /tmp

# Download with retries and follow redirects (sourceforge uses redirects)
for attempt in 1 2 3; do
    if wget --timeout=120 --tries=1 -O "${SH3D_TARBALL}" -L "${SH3D_URL}" 2>&1; then
        if [ -s "${SH3D_TARBALL}" ]; then
            echo "Download successful on attempt $attempt"
            break
        fi
    fi
    echo "Download attempt $attempt failed, retrying..."
    rm -f "${SH3D_TARBALL}"
    sleep 5
done

if [ ! -f "${SH3D_TARBALL}" ] || [ ! -s "${SH3D_TARBALL}" ]; then
    echo "ERROR: Failed to download Sweet Home 3D tarball"
    exit 1
fi

# Extract to /opt
echo "Extracting Sweet Home 3D..."
tar -xzf "${SH3D_TARBALL}" -C /opt/
mv /opt/SweetHome3D-${SH3D_VERSION} /opt/SweetHome3D

# Make the launcher executable
chmod +x /opt/SweetHome3D/SweetHome3D

# Create symlink for easy access
ln -sf /opt/SweetHome3D/SweetHome3D /usr/local/bin/SweetHome3D

# Verify installation
if [ ! -f /opt/SweetHome3D/SweetHome3D ]; then
    echo "ERROR: Sweet Home 3D installation failed"
    exit 1
fi
echo "Sweet Home 3D installed at /opt/SweetHome3D/"

# Download real .sh3d sample files from official gallery
echo "Downloading real sample home plans from official Sweet Home 3D gallery..."
mkdir -p /opt/sweethome3d_samples

# userGuideExample.sh3d - Basic user guide example (2.3 MB)
echo "Downloading userGuideExample.sh3d..."
wget -q -O /opt/sweethome3d_samples/userGuideExample.sh3d \
    "https://www.sweethome3d.com/examples/userGuideExample.sh3d" || true

# SweetHome3DExample.sh3d - Basic apartment (1.8 MB)
echo "Downloading SweetHome3DExample.sh3d..."
wget -q -O /opt/sweethome3d_samples/SweetHome3DExample.sh3d \
    "https://www.sweethome3d.com/examples/SweetHome3DExample.sh3d" || true

# SweetHome3DExample7.sh3d - Contemporary villa (7 MB)
echo "Downloading SweetHome3DExample7.sh3d..."
wget -q -O /opt/sweethome3d_samples/SweetHome3DExample7.sh3d \
    "https://www.sweethome3d.com/examples/SweetHome3DExample7.sh3d" || true

# Verify at least one sample downloaded successfully
SAMPLE_COUNT=0
for f in /opt/sweethome3d_samples/*.sh3d; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        SIZE=$(stat -c%s "$f")
        echo "  $(basename $f): ${SIZE} bytes"
        SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    else
        echo "  WARNING: $(basename $f) is missing or empty"
    fi
done

if [ "$SAMPLE_COUNT" -lt 1 ]; then
    echo "ERROR: No sample files downloaded successfully"
    exit 1
fi
echo "Downloaded $SAMPLE_COUNT sample home plans"

# Set permissions
chown -R ga:ga /opt/sweethome3d_samples
chmod -R 755 /opt/SweetHome3D

# Clean up
rm -f /tmp/${SH3D_TARBALL}

echo "=== Sweet Home 3D installation complete ==="
