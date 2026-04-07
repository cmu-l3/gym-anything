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
apt-get install -y libssl3 2>/dev/null || true

# Install additional libraries that ActivInspire may need
apt-get install -y \
    libicu66 || apt-get install -y libicu70 || apt-get install -y libicu-dev

# Install utility tools for testing and verification
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    imagemagick \
    g++ \
    python3-pip \
    python3-pillow \
    file \
    unzip \
    xvfb

# Install Python packages for verification
pip3 install --no-cache-dir pillow lxml

# Install ActivInspire from the public Promethean Linux repository. The
# currently published Ubuntu channel is focal/non-oss, so newer Ubuntu bases
# still need focal compatibility packages.
echo "=== Installing ActivInspire from official Promethean repository ==="

. /etc/os-release
if [ "${VERSION_CODENAME:-unknown}" != "focal" ]; then
    echo "WARNING: Host base is ${VERSION_CODENAME:-unknown}; Promethean publishes Ubuntu focal packages."
fi

PROMETHEAN_REPO_LIST="/etc/apt/sources.list.d/promethean-activinspire.list"
FOCAL_REPO_LIST="/etc/apt/sources.list.d/focal.list"
ACTIVINSPIRE_DEB="/tmp/activinspire.deb"
INSTALL_SUCCESS=false

echo "deb [trusted=yes] https://activsoftware.co.uk/linux/repos/ubuntu focal non-oss" > "$PROMETHEAN_REPO_LIST"
echo "deb http://archive.ubuntu.com/ubuntu focal main universe" > "$FOCAL_REPO_LIST"
apt-get update

# Install compatibility libraries needed when the host base is newer than focal.
apt-get install -y libssl1.1 2>/dev/null || true
apt-get install -y libjpeg62 2>/dev/null || true
apt-get install -y libre2-5 2>/dev/null || apt-get install -y libre2-9 2>/dev/null || true
apt-get install -y libminizip1 2>/dev/null || apt-get install -y libminizip-dev 2>/dev/null || true
apt-get install -y gstreamer1.0-libav gstreamer1.0-plugins-bad 2>/dev/null || true
apt-get install -y libwebp6 2>/dev/null || true

# Create symlinks for libwebp if needed.
if [ ! -f /usr/lib/x86_64-linux-gnu/libwebp.so.6 ] && [ -f /usr/lib/x86_64-linux-gnu/libwebp.so.7 ]; then
    ln -sf /usr/lib/x86_64-linux-gnu/libwebp.so.7 /usr/lib/x86_64-linux-gnu/libwebp.so.6
fi

echo "Trying official English metapackage install..."
if apt-get install -y activ-meta-en-us; then
    INSTALL_SUCCESS=true
else
    echo "WARNING: Official metapackage install failed; falling back to the focal .deb."
    if wget -q -O "$ACTIVINSPIRE_DEB" \
        "https://activsoftware.co.uk/linux/repos/ubuntu/pool/focal/a/ac/activinspire_2004-3.5.18-1-amd64.deb"; then
        if file "$ACTIVINSPIRE_DEB" | grep -q "Debian binary package"; then
            dpkg -i --force-depends "$ACTIVINSPIRE_DEB" 2>&1 || true
            apt-get install -f -y 2>/dev/null || true
            INSTALL_SUCCESS=true
        fi
        rm -f "$ACTIVINSPIRE_DEB"
    fi
fi

# Final fallback for fully offline/local runs.
if [ "$INSTALL_SUCCESS" = false ] && [ -f "/workspace/assets/activinspire.deb" ]; then
    echo "WARNING: Falling back to /workspace/assets/activinspire.deb"
    cp /workspace/assets/activinspire.deb "$ACTIVINSPIRE_DEB"
    dpkg -i --force-depends "$ACTIVINSPIRE_DEB" 2>&1 || true
    apt-get install -f -y 2>/dev/null || true
    rm -f "$ACTIVINSPIRE_DEB"
    INSTALL_SUCCESS=true
fi

if [ "$INSTALL_SUCCESS" = true ]; then
    echo "ActivInspire installation completed"

    # Verify installation - find the actual binary location
    INSPIRE_BIN=""
    if [ -x "/usr/local/bin/activsoftware/Inspire" ]; then
        INSPIRE_BIN="/usr/local/bin/activsoftware/Inspire"
    elif [ -x "/opt/activsoftware/activinspire/bin/Inspire" ]; then
        INSPIRE_BIN="/opt/activsoftware/activinspire/bin/Inspire"
    elif [ -x "/opt/Promethean/ActivInspire/bin/Inspire" ]; then
        INSPIRE_BIN="/opt/Promethean/ActivInspire/bin/Inspire"
    elif [ -x "/usr/bin/activinspire" ]; then
        INSPIRE_BIN="/usr/bin/activinspire"
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
export XAUTHORITY="\${XAUTHORITY:-\$HOME/.Xauthority}"
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}"
if [ -z "\${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "\$XDG_RUNTIME_DIR/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=\$XDG_RUNTIME_DIR/bus"
fi
export DESKTOP_SESSION="\${DESKTOP_SESSION:-ubuntu}"
export LIBGL_ALWAYS_SOFTWARE="\${LIBGL_ALWAYS_SOFTWARE:-1}"
export QT_QUICK_BACKEND="\${QT_QUICK_BACKEND:-software}"
export QT_OPENGL="\${QT_OPENGL:-software}"
export QTWEBENGINE_CHROMIUM_FLAGS="\${QTWEBENGINE_CHROMIUM_FLAGS:---disable-gpu}"
cd "$INSPIRE_DIR"
exec "$INSPIRE_BIN" "\$@"
EOF
        chmod +x /usr/local/bin/activinspire
        ln -sf /usr/local/bin/activinspire /usr/bin/activinspire
        echo "Created wrapper script at /usr/local/bin/activinspire"

        # The bundled panel monitor library is unstable in headless VMs and
        # frequently segfaults before the first window appears. Replace it
        # with a no-op implementation so the editor can launch consistently.
        PANEL_MONITOR_LIB="$INSPIRE_DIR/libaspannelmonitor.so.1.0.0"
        if [ -f "$PANEL_MONITOR_LIB" ]; then
            if [ ! -f "${PANEL_MONITOR_LIB}.orig" ]; then
                mv "$PANEL_MONITOR_LIB" "${PANEL_MONITOR_LIB}.orig"
            fi

            cat > /tmp/libaspannelmonitor_stub.cpp << 'EOF'
class AsPannelMonitor {
public:
    AsPannelMonitor();
    void asStopMonitoring();
    void asRunPermanentMonitor();
    int asIsDeviceConnected(int device_id, int connection_type);
};

AsPannelMonitor::AsPannelMonitor() {}

void AsPannelMonitor::asStopMonitoring() {}

void AsPannelMonitor::asRunPermanentMonitor() {}

int AsPannelMonitor::asIsDeviceConnected(int device_id, int connection_type) {
    (void)device_id;
    (void)connection_type;
    return 0;
}
EOF

            g++ -shared -fPIC \
                -Wl,-soname,libaspannelmonitor.so.1 \
                -o "$PANEL_MONITOR_LIB" \
                /tmp/libaspannelmonitor_stub.cpp
            ln -sf "$(basename "$PANEL_MONITOR_LIB")" "$INSPIRE_DIR/libaspannelmonitor.so"
            ln -sf "$(basename "$PANEL_MONITOR_LIB")" "$INSPIRE_DIR/libaspannelmonitor.so.1"
            ln -sf "$(basename "$PANEL_MONITOR_LIB")" "$INSPIRE_DIR/libaspannelmonitor.so.1.0"
            rm -f /tmp/libaspannelmonitor_stub.cpp
            echo "Replaced crashing libaspannelmonitor with a VM-safe stub"
        fi

        # ActivInspire's device initialization expects these legacy hardware
        # libraries to exist even when no Promethean hardware is attached.
        # Missing libraries lead to a crash in asInitCheckConnectedDevices().
        if [ ! -e "$INSPIRE_DIR/libactivboardex.so.1" ]; then
            gcc -shared -fPIC \
                -Wl,-soname,libactivboardex.so.1 \
                -o "$INSPIRE_DIR/libactivboardex.so.1.0.0" \
                /workspace/scripts/activboard_stub.c
            ln -sf libactivboardex.so.1.0.0 "$INSPIRE_DIR/libactivboardex.so"
            ln -sf libactivboardex.so.1.0.0 "$INSPIRE_DIR/libactivboardex.so.1"
            echo "Installed VM-safe libactivboardex stub"
        fi

        if [ ! -e "$INSPIRE_DIR/libactivlog.so.1" ]; then
            gcc -shared -fPIC \
                -Wl,-soname,libactivlog.so.1 \
                -o "$INSPIRE_DIR/libactivlog.so.1.0.0" \
                /workspace/scripts/activlog_stub.c
            ln -sf libactivlog.so.1.0.0 "$INSPIRE_DIR/libactivlog.so"
            ln -sf libactivlog.so.1.0.0 "$INSPIRE_DIR/libactivlog.so.1"
            echo "Installed VM-safe libactivlog stub"
        fi
    else
        echo "Looking for ActivInspire installation..."
        find /usr -name "*nspire*" -type f 2>/dev/null | head -20
        find /opt -name "*nspire*" -type f 2>/dev/null | head -20
        find /usr/local -name "*nspire*" -type f 2>/dev/null | head -20
    fi
fi

if [ "$INSTALL_SUCCESS" = false ]; then
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
