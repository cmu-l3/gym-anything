#!/bin/bash
set -e

echo "=== Installing JStock and dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

echo "Installing system dependencies and GUI automation tools..."
apt-get install -y \
    wget \
    curl \
    ca-certificates \
    unzip \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    xvfb

echo "Installing JStock 1.0.7.60 with bundled JRE (Linux x86)..."
# Download the JStock bundle with bundled JRE (includes Java, no separate JRE install needed)
# Official release from GitHub: https://github.com/yccheok/jstock/releases/tag/release_1-0-7-60
JRE_LINUX_URL="https://github.com/yccheok/jstock/releases/download/release_1-0-7-60/jstock-1.0.7.60-jre-linux.zip"
FALLBACK_URL="https://github.com/yccheok/jstock/releases/download/release_1-0-7-60/jstock-1.0.7.60-jre-linux.zip"

mkdir -p /opt

echo "Downloading JStock from GitHub..."
for url in "$JRE_LINUX_URL" "$FALLBACK_URL"; do
    if wget -q --timeout=120 "$url" -O /tmp/jstock.zip; then
        JSTOCK_SIZE=$(stat -c%s /tmp/jstock.zip 2>/dev/null || echo 0)
        if [ "$JSTOCK_SIZE" -gt 1000000 ]; then
            echo "JStock downloaded successfully (${JSTOCK_SIZE} bytes)"
            break
        fi
    fi
    echo "Download attempt failed or file too small, retrying..."
    sleep 5
done

# Verify download
JSTOCK_SIZE=$(stat -c%s /tmp/jstock.zip 2>/dev/null || echo 0)
if [ "$JSTOCK_SIZE" -lt 1000000 ]; then
    echo "ERROR: JStock download failed (size: ${JSTOCK_SIZE} bytes)"
    exit 1
fi

echo "Extracting JStock to /opt/jstock/..."
rm -rf /opt/jstock
mkdir -p /opt/jstock
unzip -qo /tmp/jstock.zip -d /opt/jstock/
rm -f /tmp/jstock.zip

# JStock extracts to /opt/jstock/jstock/ (nested directory)
if [ -d /opt/jstock/jstock ]; then
    mv /opt/jstock/jstock/* /opt/jstock/ 2>/dev/null || true
    rmdir /opt/jstock/jstock 2>/dev/null || true
fi

# Make scripts executable
chmod +x /opt/jstock/jstock.sh 2>/dev/null || true
chmod -R 755 /opt/jstock/

echo "JStock extracted to /opt/jstock/"
ls -la /opt/jstock/

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== JStock installation complete ==="
