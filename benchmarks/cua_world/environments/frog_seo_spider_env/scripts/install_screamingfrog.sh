#!/bin/bash
set -e

echo "=== Installing Screaming Frog SEO Spider ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install dependencies
# Screaming Frog requires Java and some GUI libraries
apt-get install -y \
    openjdk-11-jdk \
    openjdk-11-jre \
    libgtk-3-0 \
    libnotify4 \
    libnss3 \
    libxss1 \
    libxtst6 \
    xdg-utils \
    libatspi2.0-0 \
    libdrm2 \
    libgbm1 \
    libxkbcommon0 \
    fonts-liberation \
    libappindicator3-1 \
    libasound2 \
    libnspr4 \
    wget \
    curl \
    xdotool \
    wmctrl \
    scrot \
    python3-pip \
    ttf-mscorefonts-installer

# Accept MS fonts license non-interactively
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections

# Download Screaming Frog SEO Spider
echo "Downloading Screaming Frog SEO Spider..."
FROG_VERSION="23.2"
FROG_DEB="screamingfrogseospider_${FROG_VERSION}_all.deb"
FROG_URL="https://download.screamingfrog.co.uk/products/seo-spider/${FROG_DEB}"

cd /tmp
if [ ! -f "$FROG_DEB" ]; then
    wget -q --show-progress "$FROG_URL" -O "$FROG_DEB" || {
        echo "Failed to download version ${FROG_VERSION}, trying alternative..."
        # Try without version in case the version changed
        wget -q --show-progress "https://download.screamingfrog.co.uk/products/seo-spider/screamingfrogseospider_all.deb" -O "$FROG_DEB" || {
            echo "ERROR: Could not download Screaming Frog SEO Spider"
            exit 1
        }
    }
fi

# Install Screaming Frog
echo "Installing Screaming Frog SEO Spider..."
dpkg -i "$FROG_DEB" || apt-get install -f -y

# Verify installation
if command -v screamingfrogseospider &> /dev/null; then
    echo "Screaming Frog SEO Spider installed successfully"
else
    # Check alternative installation location
    if [ -f "/usr/bin/screamingfrogseospider" ] || [ -f "/opt/ScreamingFrogSEOSpider/ScreamingFrogSEOSpider" ]; then
        echo "Screaming Frog SEO Spider installed successfully (alternative path)"
    else
        echo "ERROR: Screaming Frog SEO Spider installation failed"
        exit 1
    fi
fi

# Clean up
rm -f /tmp/*.deb

# Install a simple HTTP server for local testing
apt-get install -y python3

echo "=== Screaming Frog SEO Spider installation complete ==="
