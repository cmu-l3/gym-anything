#!/bin/bash
set -e

echo "=== Installing Juris-M (Jurism) ==="

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
    ca-certificates \
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libxt6 \
    libx11-xcb1

# Download Jurism tarball (version 6.0.30m3)
JURISM_VERSION="6.0.30m3"
JURISM_URL="https://github.com/Juris-M/assets/releases/download/client/release/${JURISM_VERSION}/Jurism-${JURISM_VERSION}_linux-x86_64.tar.bz2"
JURISM_FALLBACK_URL="https://jurism.net/jurism/dl?channel=release&platform=linux-x86_64"

echo "Downloading Jurism ${JURISM_VERSION}..."
cd /tmp

# Try primary URL first, then fallback
if wget -q --timeout=120 -O jurism.tar.bz2 "$JURISM_URL"; then
    echo "Downloaded from primary URL"
elif wget -q --timeout=120 -O jurism.tar.bz2 "$JURISM_FALLBACK_URL"; then
    echo "Downloaded from fallback URL"
else
    echo "ERROR: Failed to download Jurism"
    exit 1
fi

# Extract to /opt
echo "Extracting Jurism to /opt..."
tar -xjf jurism.tar.bz2 -C /opt/

# Find extracted directory (could be Jurism_linux-x86_64 or similar)
JURISM_DIR=""
for candidate in /opt/Jurism_linux-x86_64 /opt/Jurism; do
    if [ -d "$candidate" ]; then
        JURISM_DIR="$candidate"
        break
    fi
done

# If not found by known names, search for directory containing jurism binary
if [ -z "$JURISM_DIR" ]; then
    JURISM_DIR=$(find /opt -maxdepth 1 -type d -name "Jurism*" 2>/dev/null | head -1)
fi

if [ -z "$JURISM_DIR" ]; then
    echo "ERROR: Could not find extracted Jurism directory in /opt"
    ls /opt/
    exit 1
fi

echo "Jurism directory: $JURISM_DIR"

# Rename to canonical /opt/jurism if needed
if [ "$JURISM_DIR" != "/opt/jurism" ]; then
    mv "$JURISM_DIR" /opt/jurism
fi

# Run set_launcher_icon script if it exists
if [ -f /opt/jurism/set_launcher_icon ]; then
    cd /opt/jurism
    ./set_launcher_icon || true
fi

# Install desktop file
if [ -f /opt/jurism/jurism.desktop ]; then
    cp /opt/jurism/jurism.desktop /usr/share/applications/
    chmod +x /usr/share/applications/jurism.desktop
fi

# Create symlink for easier access
# The binary inside may be called jurism or Jurism
JURISM_BIN=""
for bin_candidate in /opt/jurism/jurism /opt/jurism/Jurism; do
    if [ -f "$bin_candidate" ] && [ -x "$bin_candidate" ]; then
        JURISM_BIN="$bin_candidate"
        break
    fi
done

if [ -n "$JURISM_BIN" ]; then
    ln -sf "$JURISM_BIN" /usr/local/bin/jurism
    echo "Jurism binary linked at: /usr/local/bin/jurism -> $JURISM_BIN"
else
    echo "WARNING: Could not find jurism binary. Contents of /opt/jurism:"
    ls /opt/jurism/
fi

# Cleanup
rm -f /tmp/jurism.tar.bz2

echo "=== Jurism installation complete ==="
