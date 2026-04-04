#!/bin/bash
set -euo pipefail

echo "=== Installing QGroundControl + ArduPilot SITL ==="

export DEBIAN_FRONTEND=noninteractive

# ── 1. Update package lists ──────────────────────────────────────────────
echo "--- Updating package lists ---"
apt-get update

# ── 2. Install system dependencies ───────────────────────────────────────
echo "--- Installing system dependencies ---"
apt-get install -y \
    libfuse2 \
    gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl \
    libxcb-xinerama0 libxkbcommon-x11-0 libxcb-cursor0 \
    mesa-utils libgl1-mesa-dri libegl1-mesa libgbm1 \
    scrot wmctrl xdotool imagemagick \
    python3-pip python3-dev python3-venv \
    git git-lfs wget curl unzip \
    gcc g++ make cmake \
    lsof net-tools \
    network-manager

# ── 2b. Configure NetworkManager to manage all interfaces ─────────────────
# Qt 6 (used by QGC v5) checks NetworkManager's D-Bus API for connectivity.
# If NM reports "disconnected", QGC won't fetch map tiles even if network works.
# The base image uses systemd-networkd, so NM sees interfaces as "unmanaged".
echo "--- Configuring NetworkManager for Qt connectivity detection ---"

# Configure NM to manage all interfaces (override ifupdown managed=false default)
# NOTE: Do NOT enable NM at boot — it conflicts with systemd-networkd.
# We start NM manually in setup_qgc.sh after the network is already up.
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-manage-all.conf << 'NMCONF'
[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=no
NMCONF

# Make sure NM is NOT enabled at boot (we start it manually in post_start)
systemctl disable NetworkManager.service 2>/dev/null || true

# ── 3. Download QGroundControl AppImage ──────────────────────────────────
echo "--- Downloading QGroundControl AppImage ---"
QGC_PATH="/opt/QGroundControl-x86_64.AppImage"

if [ ! -f "$QGC_PATH" ] || [ ! -s "$QGC_PATH" ]; then
    rm -f "$QGC_PATH"
    # v5.0.8 from official GitHub releases
    wget -q -L -O "$QGC_PATH" \
        "https://github.com/mavlink/qgroundcontrol/releases/download/v5.0.8/QGroundControl-x86_64.AppImage" || {
        echo "WARNING: Primary QGC download failed, trying v4.4.3..."
        wget -q -L -O "$QGC_PATH" \
            "https://github.com/mavlink/qgroundcontrol/releases/download/v4.4.3/QGroundControl.AppImage"
    }
    chmod +x "$QGC_PATH"
    echo "QGroundControl downloaded to $QGC_PATH"
else
    echo "QGroundControl already exists at $QGC_PATH"
fi

# Verify download succeeded (file should be >100MB)
QGC_SIZE=$(stat -c%s "$QGC_PATH" 2>/dev/null || echo 0)
if [ "$QGC_SIZE" -lt 1000000 ]; then
    echo "ERROR: QGC AppImage is too small ($QGC_SIZE bytes), download may have failed"
    exit 1
fi
echo "QGC AppImage size: $QGC_SIZE bytes"

# Create wrapper script for easier launch
cat > /usr/local/bin/qgroundcontrol << 'WRAPPER'
#!/bin/bash
export LIBGL_ALWAYS_SOFTWARE=1
export QT_QUICK_BACKEND=software
export DISPLAY="${DISPLAY:-:1}"
exec /opt/QGroundControl-x86_64.AppImage --appimage-extract-and-run "$@"
WRAPPER
chmod +x /usr/local/bin/qgroundcontrol

# ── 4. Clone and build ArduPilot SITL ────────────────────────────────────
echo "--- Setting up ArduPilot SITL ---"
ARDUPILOT_DIR="/opt/ardupilot"

if [ ! -d "$ARDUPILOT_DIR" ]; then
    echo "Cloning ArduPilot (shallow clone)..."
    git clone --depth 1 --recurse-submodules --shallow-submodules \
        https://github.com/ArduPilot/ardupilot.git "$ARDUPILOT_DIR"
else
    echo "ArduPilot directory already exists"
fi

# Make ardupilot owned by ga user BEFORE building
chown -R ga:ga "$ARDUPILOT_DIR"

# Install Python dependencies for ArduPilot manually
# (install-prereqs-ubuntu.sh refuses to run as root)
echo "--- Installing ArduPilot Python dependencies ---"
pip3 install empy==3.3.4 pexpect future pymavlink MAVProxy 2>/dev/null || \
    su - ga -c "pip3 install empy==3.3.4 pexpect future pymavlink MAVProxy" || true

# Pre-build the ArduCopter SITL binary as ga user
echo "--- Pre-building ArduCopter SITL binary ---"
su - ga -c "cd $ARDUPILOT_DIR && python3 ./waf configure --board sitl" 2>&1 | tail -5
su - ga -c "cd $ARDUPILOT_DIR && python3 ./waf copter" 2>&1 | tail -10

if [ -f "$ARDUPILOT_DIR/build/sitl/bin/arducopter" ]; then
    echo "ArduCopter SITL binary built successfully"
    ls -la "$ARDUPILOT_DIR/build/sitl/bin/arducopter"
else
    echo "ERROR: ArduCopter binary not found"
    exit 1
fi

# ── 5. Set up PATH for ga user ──────────────────────────────────────────
echo "--- Configuring user environment ---"
cat >> /home/ga/.bashrc << 'BASHRC'

# ArduPilot paths
export PATH="/opt/ardupilot/Tools/autotest:$PATH"
export PATH="$HOME/.local/bin:$PATH"
BASHRC
chown ga:ga /home/ga/.bashrc

# ── 6. Disable ModemManager (causes QGC serial port warnings) ───────────
systemctl mask --now ModemManager.service 2>/dev/null || true

echo "=== QGroundControl + ArduPilot SITL installation complete ==="
echo "QGC: $QGC_PATH ($(stat -c%s "$QGC_PATH") bytes)"
echo "ArduPilot: $ARDUPILOT_DIR"
ls -la "$ARDUPILOT_DIR/build/sitl/bin/arducopter"
