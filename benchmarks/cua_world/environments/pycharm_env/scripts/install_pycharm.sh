#!/bin/bash
set -e

echo "=== Installing PyCharm Community Edition ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Fix potential apt_pkg issues (common in some Ubuntu images)
# The cnf-update-db script can fail if apt_pkg is missing
if [ -f /usr/lib/cnf-update-db ]; then
    chmod -x /usr/lib/cnf-update-db 2>/dev/null || true
fi

# Update package lists - ignore non-critical errors from post-invoke hooks
apt-get update || {
    echo "Warning: apt-get update had some errors, continuing anyway..."
}

# Install Python 3.11 and development tools
echo "Installing Python 3.11 and development tools..."
apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3.11-dev \
    python3-pip \
    python3-setuptools \
    python3-wheel

# Make Python 3.11 the default python3
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 || true
update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 || true

# Install common Python packages
pip3 install --upgrade pip setuptools wheel

# Install GUI automation and utility tools
apt-get install -y \
    wget \
    curl \
    ca-certificates \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    imagemagick \
    scrot \
    git \
    jq

# Install common Python development packages
# Use --ignore-installed to avoid conflicts with system packages
echo "Installing common Python development packages..."
pip3 install --ignore-installed \
    pytest \
    pytest-cov \
    black \
    flake8 \
    mypy \
    requests \
    flask \
    numpy \
    pandas || {
    echo "Warning: Some pip packages may have failed, but continuing..."
}

# Download PyCharm Community Edition
echo "Downloading PyCharm Community Edition..."
PYCHARM_VERSION="2024.3"
# Use the CDN URL which is more reliable
PYCHARM_DOWNLOAD_URL="https://download-cdn.jetbrains.com/python/pycharm-community-${PYCHARM_VERSION}.tar.gz"

echo "Downloading from: $PYCHARM_DOWNLOAD_URL"
# Use -L to follow redirects, and show progress
if ! wget -L --progress=dot:giga "$PYCHARM_DOWNLOAD_URL" -O /tmp/pycharm.tar.gz; then
    echo "Failed to download PyCharm from CDN, trying alternate URL..."
    PYCHARM_DOWNLOAD_URL="https://download.jetbrains.com/python/pycharm-community-${PYCHARM_VERSION}.tar.gz"
    echo "Trying: $PYCHARM_DOWNLOAD_URL"
    if ! wget -L --progress=dot:giga "$PYCHARM_DOWNLOAD_URL" -O /tmp/pycharm.tar.gz; then
        echo "ERROR: Failed to download PyCharm!"
        exit 1
    fi
fi

# Verify the download is a valid gzip file
if ! file /tmp/pycharm.tar.gz | grep -q "gzip"; then
    echo "ERROR: Downloaded file is not a valid gzip archive!"
    echo "File type: $(file /tmp/pycharm.tar.gz)"
    cat /tmp/pycharm.tar.gz | head -c 500
    exit 1
fi

echo "Download completed successfully ($(du -h /tmp/pycharm.tar.gz | cut -f1))"

# Extract PyCharm to /opt/pycharm
echo "Extracting PyCharm..."
mkdir -p /opt/pycharm
tar -xzf /tmp/pycharm.tar.gz -C /opt/pycharm --strip-components=1
rm -f /tmp/pycharm.tar.gz

# Create symlink for easy access
ln -sf /opt/pycharm/bin/pycharm.sh /usr/local/bin/pycharm

# Verify installation
if [ -f /opt/pycharm/bin/pycharm.sh ]; then
    echo "PyCharm installed at /opt/pycharm"
    ls -la /opt/pycharm/bin/pycharm.sh
else
    echo "ERROR: PyCharm installation failed!"
    exit 1
fi

# Verify Python installation
python3 --version 2>&1 || echo "WARNING: Python not accessible"
pip3 --version 2>&1 || echo "WARNING: pip not accessible"

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== PyCharm installation complete ==="
