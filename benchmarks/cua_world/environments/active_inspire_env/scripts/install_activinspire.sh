#!/bin/bash
set -e

echo "=== Installing ActivInspire and dependencies ==="

# Non-interactive apt configuration
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install core dependencies for ActivInspire
# ActivInspire requires various Qt and multimedia libraries
apt-get install -y \
    wget \
    curl \
    gnupg \
    ca-certificates \
    software-properties-common

# Install X11, display, and multimedia dependencies
apt-get install -y \
    libxcb-xinerama0 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-randr0 \
    libxcb-render-util0 \
    libxcb-shape0 \
    libxcb-sync1 \
    libxcb-xfixes0 \
    libxcb-xkb1 \
    libxkbcommon-x11-0 \
    libxkbcommon0 \
    libfontconfig1 \
    libfreetype6 \
    libgl1-mesa-glx \
    libglu1-mesa \
    libasound2 \
    libpulse0 \
    libpulse-mainloop-glib0

# Install Qt dependencies (ActivInspire uses Qt)
apt-get install -y \
    libqt5core5a \
    libqt5gui5 \
    libqt5widgets5 \
    libqt5network5 \
    libqt5printsupport5 \
    libqt5svg5 \
    libqt5multimedia5 \
    libqt5multimediawidgets5 \
    libqt5opengl5 \
    libqt5webkit5 \
    libqt5xml5 \
    libqt5dbus5 \
    qt5-gtk-platformtheme

# Install SSL and crypto libraries
apt-get install -y \
    libssl1.1 || apt-get install -y libssl3

# Install additional libraries that ActivInspire may need
apt-get install -y \
    libicu66 || apt-get install -y libicu70 || apt-get install -y libicu-dev

# Install utility tools for testing and verification
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    python3-pip \
    python3-pillow \
    file \
    unzip \
    xvfb

# Install Python packages for verification
pip3 install --no-cache-dir pillow lxml

# Download ActivInspire
# Note: ActivInspire requires registration on Promethean website
# The package may need to be downloaded manually or via direct link
# Using the latest available Ubuntu 20.04 compatible version

echo "=== Downloading ActivInspire ==="

ACTIVINSPIRE_DEB="/tmp/activinspire.deb"

# List of URLs to try (from most likely to work to least)
ACTIVINSPIRE_URLS=(
    "http://activsoftware.co.uk/linux/repos/ubuntu/pool/focal/a/ac/activinspire_2004-3.5.18-1-amd64.deb"
    "http://activsoftware.co.uk/linux/repos/ubuntu/pool/jammy/a/ac/activinspire_2004-3.5.18-1-amd64.deb"
    "https://filescdn.prometheanworld.com/Software/ActivInspire/Linux/activinspire_2004-3.5.18-1-amd64.deb"
    "https://filescdn.prometheanworld.com/Software/ActivInspire/Linux/activinspire-2004-3.4.16-1-amd64.deb"
)

DOWNLOAD_SUCCESS=false

for url in "${ACTIVINSPIRE_URLS[@]}"; do
    echo "Trying to download from: $url"
    if wget --no-check-certificate -q -O "$ACTIVINSPIRE_DEB" "$url" 2>/dev/null; then
        # Verify it's a valid deb file
        if file "$ACTIVINSPIRE_DEB" | grep -q "Debian binary package"; then
            echo "Successfully downloaded ActivInspire from: $url"
            DOWNLOAD_SUCCESS=true
            break
        else
            echo "Downloaded file is not a valid Debian package, trying next URL..."
            rm -f "$ACTIVINSPIRE_DEB"
        fi
    else
        echo "Failed to download from: $url"
    fi
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "WARNING: Could not download ActivInspire from any known URL."
    echo "Please manually download ActivInspire from:"
    echo "  https://www.prometheanworld.com/products/software/activinspire/"
    echo "And place the .deb file at: $ACTIVINSPIRE_DEB"

    # Check if the package is already available in workspace
    if [ -f "/workspace/assets/activinspire.deb" ]; then
        cp /workspace/assets/activinspire.deb "$ACTIVINSPIRE_DEB"
        echo "Found ActivInspire in workspace assets"
        DOWNLOAD_SUCCESS=true
    fi
fi

# Install ActivInspire if the package exists
if [ -f "$ACTIVINSPIRE_DEB" ] && [ "$DOWNLOAD_SUCCESS" = true ]; then
    echo "=== Installing ActivInspire package ==="

    # Add Ubuntu Focal repository for older dependencies
    echo "Adding Ubuntu Focal repository for dependencies..."
    echo "deb http://archive.ubuntu.com/ubuntu focal main universe" > /etc/apt/sources.list.d/focal.list
    apt-get update

    # Install specific dependencies from Focal that ActivInspire needs
    apt-get install -y libjpeg62 2>/dev/null || true
    apt-get install -y libre2-5 2>/dev/null || apt-get install -y libre2-9 2>/dev/null || true
    apt-get install -y libminizip1 2>/dev/null || apt-get install -y libminizip-dev 2>/dev/null || true
    apt-get install -y gstreamer1.0-libav gstreamer1.0-plugins-bad 2>/dev/null || true
    apt-get install -y libwebp6 2>/dev/null || true

    # Create symlinks for libwebp if needed
    if [ ! -f /usr/lib/x86_64-linux-gnu/libwebp.so.6 ] && [ -f /usr/lib/x86_64-linux-gnu/libwebp.so.7 ]; then
        ln -sf /usr/lib/x86_64-linux-gnu/libwebp.so.7 /usr/lib/x86_64-linux-gnu/libwebp.so.6
    fi

    # Install ActivInspire with force-depends to handle missing deps
    echo "Installing ActivInspire package..."
    dpkg -i --force-depends "$ACTIVINSPIRE_DEB" 2>&1 || true

    # Try to fix dependencies
    apt-get install -f -y 2>/dev/null || true

    rm -f "$ACTIVINSPIRE_DEB"

    # Remove Focal repository to avoid conflicts
    rm -f /etc/apt/sources.list.d/focal.list
    apt-get update

    echo "ActivInspire installation completed"

    # Verify installation - find the actual binary location
    INSPIRE_BIN=""
    if [ -x "/usr/bin/activinspire" ]; then
        INSPIRE_BIN="/usr/bin/activinspire"
    elif [ -x "/usr/local/bin/activsoftware/Inspire" ]; then
        INSPIRE_BIN="/usr/local/bin/activsoftware/Inspire"
    elif [ -x "/opt/activsoftware/activinspire/bin/Inspire" ]; then
        INSPIRE_BIN="/opt/activsoftware/activinspire/bin/Inspire"
    elif [ -x "/opt/Promethean/ActivInspire/bin/Inspire" ]; then
        INSPIRE_BIN="/opt/Promethean/ActivInspire/bin/Inspire"
    fi

    if [ -n "$INSPIRE_BIN" ]; then
        echo "ActivInspire binary found at: $INSPIRE_BIN"

        # Create wrapper script with comprehensive library paths
        # Include all subdirectories that contain .so files
        INSPIRE_DIR=$(dirname "$INSPIRE_BIN")
        cat > /usr/local/bin/activinspire << EOF
#!/bin/bash
export LD_LIBRARY_PATH="$INSPIRE_DIR:$INSPIRE_DIR/helperPlugins:$INSPIRE_DIR/imageformats:$INSPIRE_DIR/platforms:$INSPIRE_DIR/printsupport:$INSPIRE_DIR/sqldrivers:$INSPIRE_DIR/tls:$INSPIRE_DIR/xcbglintegrations:\$LD_LIBRARY_PATH"
export QT_QPA_PLATFORM=xcb
export QT_X11_NO_MITSHM=1
cd "$INSPIRE_DIR"
exec "$INSPIRE_BIN" "\$@"
EOF
        chmod +x /usr/local/bin/activinspire
        echo "Created wrapper script at /usr/local/bin/activinspire"
    else
        echo "Looking for ActivInspire installation..."
        find /usr -name "*nspire*" -type f 2>/dev/null | head -20
        find /opt -name "*nspire*" -type f 2>/dev/null | head -20
        find /usr/local -name "*nspire*" -type f 2>/dev/null | head -20
    fi
else
    echo "WARNING: ActivInspire package not found. Installation may be incomplete."
    echo "The environment may need manual installation."
fi

# Install 32-bit dependencies if needed (for some ActivInspire features)
dpkg --add-architecture i386 2>/dev/null || true
apt-get update
apt-get install -y libc6:i386 libncurses5:i386 libstdc++6:i386 2>/dev/null || true

# Create required directories
mkdir -p /home/ga/.activsoftware
mkdir -p /home/ga/Documents/Flipcharts
mkdir -p /home/ga/.local/share/applications

# Set ownership
chown -R ga:ga /home/ga/.activsoftware
chown -R ga:ga /home/ga/Documents

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== ActivInspire installation complete ==="
