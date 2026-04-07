#!/bin/bash
# set -euo pipefail

echo "=== Installing Apache OpenOffice and related packages ==="

# Skip if already installed
if [ -x "/opt/openoffice4/program/soffice" ]; then
    echo "Apache OpenOffice already installed, skipping installation."
    /opt/openoffice4/program/soffice --version 2>/dev/null || true
    exit 0
fi

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package manager
apt-get update

# Install Java (required for OpenOffice)
echo "Installing Java runtime..."
apt-get install -y \
    default-jre \
    default-jdk

# Remove LibreOffice if installed (OpenOffice conflicts with it)
echo "Removing LibreOffice (conflicts with Apache OpenOffice)..."
apt-get remove -y libreoffice* --purge 2>/dev/null || true
apt-get autoremove -y || true

# Install dependencies
echo "Installing dependencies..."
apt-get install -y \
    wget \
    curl \
    ca-certificates \
    libxinerama1 \
    libxtst6 \
    libxt6 \
    libxrender1 \
    libfontconfig1 \
    libfreetype6 \
    libcups2 \
    libglib2.0-0 \
    libgtk-3-0

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot

# Install file handling utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    tar

# Install Python libraries for document verification
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-dev \
    python3-lxml

pip3 install --no-cache-dir --break-system-packages \
    python-docx \
    odfpy \
    lxml 2>/dev/null || \
pip3 install --no-cache-dir \
    python-docx \
    odfpy \
    lxml || true

# Download Apache OpenOffice
echo "Downloading Apache OpenOffice 4.1.16..."
OPENOFFICE_VERSION="4.1.16"
OPENOFFICE_FILE="Apache_OpenOffice_${OPENOFFICE_VERSION}_Linux_x86-64_install-deb_en-US.tar.gz"

# Use Apache archive as primary (fast, reliable) and SourceForge as fallback
URLS=(
    "https://archive.apache.org/dist/openoffice/${OPENOFFICE_VERSION}/binaries/en-US/${OPENOFFICE_FILE}"
    "https://downloads.apache.org/openoffice/${OPENOFFICE_VERSION}/binaries/en-US/${OPENOFFICE_FILE}"
    "https://sourceforge.net/projects/openofficeorg.mirror/files/${OPENOFFICE_VERSION}/binaries/en-US/${OPENOFFICE_FILE}/download"
)

cd /tmp

DOWNLOADED=false
for url in "${URLS[@]}"; do
    echo "Trying: $url"
    for attempt in 1 2 3; do
        echo "  Attempt $attempt..."
        if wget --timeout=120 --tries=1 -c -q --show-progress -O "${OPENOFFICE_FILE}" "$url"; then
            # Verify file is non-empty and reasonably sized (>100MB)
            FILE_SIZE=$(stat -c%s "${OPENOFFICE_FILE}" 2>/dev/null || echo 0)
            if [ "$FILE_SIZE" -gt 100000000 ]; then
                echo "  Download successful (${FILE_SIZE} bytes)"
                DOWNLOADED=true
                break 2
            else
                echo "  File too small (${FILE_SIZE} bytes), retrying..."
                rm -f "${OPENOFFICE_FILE}"
            fi
        else
            echo "  Download attempt $attempt failed"
            rm -f "${OPENOFFICE_FILE}"
        fi
        sleep 2
    done
done

# Verify download
if [ "$DOWNLOADED" != "true" ] || [ ! -f "${OPENOFFICE_FILE}" ] || [ ! -s "${OPENOFFICE_FILE}" ]; then
    echo "ERROR: Failed to download Apache OpenOffice"
    exit 1
fi

# Extract the archive
echo "Extracting Apache OpenOffice..."
tar -xzf "${OPENOFFICE_FILE}"

# Find the extracted directory
EXTRACTED_DIR=$(ls -d en-US 2>/dev/null || ls -d */DEBS 2>/dev/null | head -1 | dirname)
if [ -d "en-US" ]; then
    EXTRACTED_DIR="en-US"
fi

# Install the DEB packages
echo "Installing Apache OpenOffice packages..."
cd "${EXTRACTED_DIR}/DEBS"
dpkg -i *.deb

# Install desktop integration
echo "Installing desktop integration..."
cd desktop-integration
dpkg -i *.deb || true

# Cleanup
echo "Cleaning up..."
cd /tmp
rm -rf "${OPENOFFICE_FILE}" "${EXTRACTED_DIR}" en-US

# Create symlink for easier access
if [ -x "/opt/openoffice4/program/soffice" ]; then
    ln -sf /opt/openoffice4/program/soffice /usr/local/bin/soffice
    ln -sf /opt/openoffice4/program/swriter /usr/local/bin/swriter 2>/dev/null || true
fi

# Install additional fonts
echo "Installing additional fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-liberation2 \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-crosextra-carlito \
    fonts-crosextra-caladea \
    fonts-opensymbol

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Apache OpenOffice installation completed ==="

# Verify installation (just check binary exists, don't run --version as it
# triggers the first-run wizard before user profile is configured)
if [ -x "/opt/openoffice4/program/soffice" ]; then
    echo "Apache OpenOffice installed successfully at /opt/openoffice4"
    ls -la /opt/openoffice4/program/soffice
else
    echo "WARNING: Apache OpenOffice binary not found at expected location"
    ls -la /opt/ 2>/dev/null || true
fi
