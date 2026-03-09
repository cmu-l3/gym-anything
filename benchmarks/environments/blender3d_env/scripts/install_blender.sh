#!/bin/bash
set -e

echo "=== Installing Blender 3D ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install base dependencies
echo "Installing base dependencies..."
apt-get install -y \
    wget \
    curl \
    unzip \
    xz-utils \
    libssl-dev \
    libfuse2 \
    libglu1-mesa \
    libxi6 \
    libxrender1 \
    libxkbcommon0 \
    libsm6 \
    libice6 \
    libxext6 \
    libx11-6 \
    libxxf86vm1 \
    libxfixes3 \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libfreetype6 \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libopenjp2-7 \
    libwebp7 \
    libopenexr-dev \
    scrot \
    wmctrl \
    xdotool \
    python3-pip \
    python3-venv \
    ffmpeg \
    imagemagick

# Install OpenGL/Mesa dependencies for software and hardware rendering
echo "Installing OpenGL/Mesa dependencies..."
apt-get install -y \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    libegl1-mesa \
    libgbm1 \
    mesa-utils \
    mesa-vulkan-drivers \
    libvulkan1 \
    vulkan-tools || true

# Install OpenCL support for GPU compute
echo "Installing OpenCL support..."
apt-get install -y \
    ocl-icd-opencl-dev \
    ocl-icd-libopencl1 \
    opencl-headers \
    clinfo || true

# Check for GPU drivers and install NVIDIA if available
echo "Checking GPU availability..."
if lspci | grep -i nvidia > /dev/null 2>&1; then
    echo "NVIDIA GPU detected, installing drivers..."
    apt-get install -y \
        nvidia-driver \
        nvidia-opencl-icd \
        libcuda1 || echo "Warning: Could not install NVIDIA drivers"
else
    echo "No NVIDIA GPU detected, using software/Mesa rendering"
    apt-get install -y \
        mesa-opencl-icd || true
fi

# Create installation directory
INSTALL_DIR="/opt/blender-install"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download Blender LTS (latest stable)
# Using Blender 4.2 LTS as the stable version
BLENDER_VERSION="4.2.4"
BLENDER_MAJOR="4.2"
BLENDER_ARCHIVE="blender-${BLENDER_VERSION}-linux-x64.tar.xz"
BLENDER_URL="https://download.blender.org/release/Blender${BLENDER_MAJOR}/${BLENDER_ARCHIVE}"

echo "Downloading Blender ${BLENDER_VERSION}..."
if wget -q --show-progress "$BLENDER_URL" -O "$BLENDER_ARCHIVE"; then
    echo "Download successful"
else
    echo "Primary download failed, trying mirror..."
    # Try mirror
    BLENDER_MIRROR="https://mirrors.ocf.berkeley.edu/blender/release/Blender${BLENDER_MAJOR}/${BLENDER_ARCHIVE}"
    wget -q --show-progress "$BLENDER_MIRROR" -O "$BLENDER_ARCHIVE" || {
        echo "ERROR: Could not download Blender"
        exit 1
    }
fi

# Extract Blender
echo "Extracting Blender..."
tar -xJf "$BLENDER_ARCHIVE"

# Find extracted directory (the one containing the blender binary)
BLENDER_DIR=$(find "$INSTALL_DIR" -maxdepth 2 -type f -name "blender" -executable | head -1 | xargs dirname 2>/dev/null)

if [ -z "$BLENDER_DIR" ] || [ ! -d "$BLENDER_DIR" ]; then
    echo "Could not find blender binary, trying alternative search..."
    BLENDER_DIR=$(find "$INSTALL_DIR" -maxdepth 1 -type d -name "blender-*" | head -1)
fi

if [ -z "$BLENDER_DIR" ] || [ ! -d "$BLENDER_DIR" ]; then
    echo "ERROR: Could not find extracted Blender directory"
    echo "Contents of $INSTALL_DIR:"
    ls -la "$INSTALL_DIR"
    exit 1
fi

echo "Found Blender directory: $BLENDER_DIR"

# Move to /opt/blender
echo "Installing Blender to /opt/blender..."
rm -rf /opt/blender
mv "$BLENDER_DIR" /opt/blender

# Verify the binary exists
if [ ! -x "/opt/blender/blender" ]; then
    # Maybe nested one more level?
    NESTED=$(find /opt/blender -maxdepth 2 -type f -name "blender" -executable | head -1)
    if [ -n "$NESTED" ]; then
        NESTED_DIR=$(dirname "$NESTED")
        echo "Found nested Blender at $NESTED_DIR, relocating..."
        mv "$NESTED_DIR"/* /opt/blender/ 2>/dev/null || true
        rm -rf /opt/blender/blender-* 2>/dev/null || true
    fi
fi

# Create symlinks
ln -sf /opt/blender/blender /usr/local/bin/blender

# Verify installation
if [ -x "/opt/blender/blender" ]; then
    echo "Blender installed successfully"
    /opt/blender/blender --version
else
    echo "ERROR: Blender installation failed"
    echo "Contents of /opt/blender:"
    ls -la /opt/blender/
    exit 1
fi

# Create desktop entry
cat > /usr/share/applications/blender.desktop << 'EOF'
[Desktop Entry]
Name=Blender
GenericName=3D Modeler
Comment=Create 3D graphics, animations, and visual effects
Exec=/opt/blender/blender %f
Icon=/opt/blender/blender.svg
Terminal=false
Type=Application
Categories=Graphics;3DGraphics;
MimeType=application/x-blender;
EOF

# Install Python packages for verification
echo "Installing Python verification packages..."
pip3 install --quiet opencv-python-headless pillow numpy || true

# Download official demo files for realistic testing
echo "Downloading Blender demo files..."
DEMO_DIR="/home/ga/BlenderDemos"
mkdir -p "$DEMO_DIR"
cd "$DEMO_DIR"

# Download official Blender demo files
# Splash screen files and sample scenes
DEMO_FILES=(
    "https://download.blender.org/demo/test/benchmark.zip"
)

for demo_url in "${DEMO_FILES[@]}"; do
    demo_file=$(basename "$demo_url")
    echo "Downloading $demo_file..."
    wget -q "$demo_url" -O "$demo_file" 2>/dev/null || echo "Could not download $demo_file (optional)"
done

# Extract any zip files
for zipfile in *.zip; do
    if [ -f "$zipfile" ]; then
        unzip -q -o "$zipfile" -d "${zipfile%.zip}" 2>/dev/null || true
    fi
done

# Set permissions
chown -R ga:ga "$DEMO_DIR"

# Clean up installation files
cd /
rm -rf "$INSTALL_DIR"

echo "=== Blender 3D installation complete ==="
echo "Blender version: $(/opt/blender/blender --version | head -1)"
echo "Demo files: $DEMO_DIR"
