#!/bin/bash
set -euo pipefail

echo "=== Installing WPS Office (WPS Presentation) ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -q

# Install system dependencies and UI automation tools
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    wget \
    curl \
    unzip \
    libxcb-cursor0 \
    libgl1-mesa-glx \
    xfonts-utils \
    fonts-liberation \
    cabextract \
    libglu1-mesa

echo "=== Downloading WPS Office .deb package (v11.1.0.11723) ==="
mkdir -p /tmp/wps_install

WPS_DEB="/tmp/wps_install/wps-office_11.1.0.11723.XA_amd64.deb"
WPS_URL="https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/11723/wps-office_11.1.0.11723.XA_amd64.deb"

wget -q --show-progress -O "$WPS_DEB" "$WPS_URL"

DEB_SIZE=$(stat -c%s "$WPS_DEB" 2>/dev/null || echo 0)
if [ "$DEB_SIZE" -lt 100000000 ]; then
    echo "ERROR: WPS Office .deb is only ${DEB_SIZE} bytes (expected ~400MB+)"
    echo "Download failed or file is truncated. Check network connectivity."
    exit 1
fi
echo "WPS Office .deb downloaded: ${DEB_SIZE} bytes"

echo "=== Installing WPS Office .deb ==="
dpkg -i "$WPS_DEB" || true
apt-get install -f -y

# Verify installation
if ! which wpp > /dev/null 2>&1; then
    echo "ERROR: wpp binary not found after installation"
    exit 1
fi
echo "WPS Presentation installed at: $(which wpp)"

echo "=== Installing WPS missing fonts (Wingdings, Symbol, MT Extra) ==="
mkdir -p /usr/share/fonts/wps-office

# Download missing fonts that WPS warns about on first run
FONTS_URL="https://github.com/iykrichie/wps-office-19-missing-fonts-on-Linux/archive/refs/heads/master.zip"
wget -q -O /tmp/wps_fonts.zip "$FONTS_URL" && {
    unzip -q /tmp/wps_fonts.zip -d /tmp/wps_fonts_extract/
    find /tmp/wps_fonts_extract/ -name "*.ttf" -exec cp {} /usr/share/fonts/wps-office/ \; 2>/dev/null || true
    find /tmp/wps_fonts_extract/ -name "*.TTF" -exec cp {} /usr/share/fonts/wps-office/ \; 2>/dev/null || true
    fc-cache -fv /usr/share/fonts/wps-office/ 2>/dev/null || true
    echo "WPS missing fonts installed"
    rm -rf /tmp/wps_fonts.zip /tmp/wps_fonts_extract/
} || echo "WARN: Could not download WPS fonts package (non-fatal, font warnings may appear)"

echo "=== Downloading real presentation data files ==="
mkdir -p /opt/wps_samples

# Download a real multi-slide presentation:
# Apache HTTP Server performance analysis from Apache POI project test suite
# (48 slides, 633KB, real performance benchmark content)
# Source: https://github.com/apache/poi/tree/trunk/test-data/slideshow
# License: Apache License 2.0
PPTX_URL="https://raw.githubusercontent.com/apache/poi/trunk/test-data/slideshow/2411-Performance_Up.pptx"

echo "Downloading Apache performance presentation (real 48-slide PPTX)..."
wget -q -O /opt/wps_samples/performance.pptx "$PPTX_URL"

PPTX_SIZE=$(stat -c%s /opt/wps_samples/performance.pptx 2>/dev/null || echo 0)
if [ "$PPTX_SIZE" -lt 50000 ]; then
    echo "ERROR: performance.pptx is only ${PPTX_SIZE} bytes (expected ~633KB)."
    echo "Download from Apache POI repo failed. Cannot proceed without real presentation data."
    echo "URL attempted: $PPTX_URL"
    exit 1
fi
echo "performance.pptx downloaded successfully: ${PPTX_SIZE} bytes"
echo "  Source: Apache POI test data (Apache HTTP Server performance benchmarks, 48 slides)"
echo "  License: Apache License 2.0"

chmod -R 755 /opt/wps_samples

# Cleanup
rm -rf /tmp/wps_install
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== WPS Office installation complete ==="
echo "  WPS Presentation (wpp): $(which wpp)"
echo "  WPS binary directory: /opt/kingsoft/wps-office/office6/"
echo "  Real PPTX data: /opt/wps_samples/performance.pptx (${PPTX_SIZE} bytes)"
