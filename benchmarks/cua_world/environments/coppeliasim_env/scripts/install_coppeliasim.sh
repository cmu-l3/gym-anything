#!/bin/bash
set -euo pipefail

echo "=== Installing CoppeliaSim EDU ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Install base dependencies
echo "Installing base dependencies..."
apt-get install -y \
    wget curl tar xz-utils unzip \
    build-essential pkg-config cmake \
    python3 python3-pip python3-venv

# Install graphics and display dependencies
echo "Installing graphics dependencies..."
apt-get install -y \
    libx11-6 libxcb1 libxau6 \
    libgl1-mesa-dev libgl1-mesa-dri mesa-utils \
    libglu1-mesa-dev \
    xvfb dbus-x11 x11-utils libxkbcommon-x11-0 \
    libxrender1 libxrandr2 libxfixes3 libxcursor1 \
    libxi6 libxtst6

# Install multimedia dependencies (for video codecs in CoppeliaSim)
echo "Installing multimedia dependencies..."
apt-get install -y \
    libavcodec-dev libavformat-dev libswscale-dev \
    libraw1394-11 libmpfr6 libusb-1.0-0

# Install Qt5 dependencies (CoppeliaSim uses Qt)
echo "Installing Qt5 dependencies..."
apt-get install -y \
    libqt5core5a libqt5gui5 libqt5widgets5 libqt5opengl5 \
    libqt5printsupport5 libqt5network5 \
    qt5-gtk-platformtheme

# Install GUI automation tools
echo "Installing GUI automation tools..."
apt-get install -y \
    xdotool wmctrl scrot imagemagick \
    python3-pil python3-numpy

# Download CoppeliaSim EDU
echo "Downloading CoppeliaSim EDU..."
CSIM_VERSION="V4_9_0_rev6"
CSIM_TAR="CoppeliaSim_Edu_${CSIM_VERSION}_Ubuntu22_04.tar.xz"
CSIM_URL="https://downloads.coppeliarobotics.com/${CSIM_VERSION}/${CSIM_TAR}"

cd /tmp
if ! wget -q --show-progress -O "${CSIM_TAR}" "${CSIM_URL}"; then
    echo "Primary download failed, trying alternative version..."
    CSIM_VERSION="V4_9_0_rev2"
    CSIM_TAR="CoppeliaSim_Edu_${CSIM_VERSION}_Ubuntu22_04.tar.xz"
    CSIM_URL="https://downloads.coppeliarobotics.com/${CSIM_VERSION}/${CSIM_TAR}"
    wget -q --show-progress -O "${CSIM_TAR}" "${CSIM_URL}"
fi

# Extract to /opt
echo "Extracting CoppeliaSim..."
tar -xf "${CSIM_TAR}" -C /opt/
# The extracted folder name varies, find and rename it
EXTRACTED_DIR=$(ls -d /opt/CoppeliaSim_Edu_* 2>/dev/null | head -1)
if [ -z "$EXTRACTED_DIR" ]; then
    echo "ERROR: Could not find extracted CoppeliaSim directory"
    ls -la /opt/
    exit 1
fi
mv "$EXTRACTED_DIR" /opt/CoppeliaSim

# Verify the installation
echo "Verifying installation..."
ls -la /opt/CoppeliaSim/
if [ ! -f /opt/CoppeliaSim/coppeliaSim.sh ]; then
    echo "ERROR: coppeliaSim.sh not found"
    exit 1
fi

# Make executable
chmod +x /opt/CoppeliaSim/coppeliaSim.sh
chmod +x /opt/CoppeliaSim/coppeliaSim

# Set environment variables system-wide
cat > /etc/profile.d/coppeliasim.sh << 'EOF'
export COPPELIASIM_ROOT_DIR=/opt/CoppeliaSim
export PATH="/opt/CoppeliaSim:$PATH"
export LD_LIBRARY_PATH="/opt/CoppeliaSim:${LD_LIBRARY_PATH:-}"
export QT_QPA_PLATFORM_PLUGIN_PATH="/opt/CoppeliaSim"
export LIBGL_ALWAYS_SOFTWARE=1
EOF
chmod +x /etc/profile.d/coppeliasim.sh
source /etc/profile.d/coppeliasim.sh

# Also set for ga user
cat >> /home/ga/.bashrc << 'EOF'
export COPPELIASIM_ROOT_DIR=/opt/CoppeliaSim
export PATH="/opt/CoppeliaSim:$PATH"
export LD_LIBRARY_PATH="/opt/CoppeliaSim:${LD_LIBRARY_PATH:-}"
export QT_QPA_PLATFORM_PLUGIN_PATH="/opt/CoppeliaSim"
export LIBGL_ALWAYS_SOFTWARE=1
EOF

# Install Python packages for remote API and verification
pip3 install --break-system-packages cbor pyzmq pillow numpy opencv-python-headless 2>/dev/null || \
pip3 install cbor pyzmq pillow numpy opencv-python-headless

# Create a convenience launcher script
cat > /usr/local/bin/coppeliasim << 'LAUNCHER'
#!/bin/bash
export COPPELIASIM_ROOT_DIR=/opt/CoppeliaSim
export LD_LIBRARY_PATH="/opt/CoppeliaSim:${LD_LIBRARY_PATH:-}"
export QT_QPA_PLATFORM_PLUGIN_PATH="/opt/CoppeliaSim"
export LIBGL_ALWAYS_SOFTWARE=1
cd /opt/CoppeliaSim
./coppeliaSim.sh "$@"
LAUNCHER
chmod +x /usr/local/bin/coppeliasim

# Create desktop entry
cat > /usr/share/applications/coppeliasim.desktop << 'DESKTOP'
[Desktop Entry]
Name=CoppeliaSim
Comment=Robot Simulation Environment
Exec=/usr/local/bin/coppeliasim
Icon=/opt/CoppeliaSim/coppeliaSim.png
Terminal=false
Type=Application
Categories=Education;Science;Engineering;
StartupNotify=true
DESKTOP

# List available demo scenes
echo "Available demo scenes:"
ls /opt/CoppeliaSim/scenes/*.ttt 2>/dev/null | head -20
echo "---"
ls /opt/CoppeliaSim/scenes/*/*.ttt 2>/dev/null | head -20

# List available robot models
echo "Available robot models:"
find /opt/CoppeliaSim/models/robots -name "*.ttm" 2>/dev/null | head -20

# Clean up
rm -f /tmp/${CSIM_TAR}

echo "=== CoppeliaSim installation complete ==="
echo "Version: $(ls /opt/CoppeliaSim/system/ 2>/dev/null | head -3)"
echo "Install dir: /opt/CoppeliaSim"
echo "Launch: coppeliasim"
