#!/bin/bash
set -euo pipefail

echo "=== Installing QBlade CE and dependencies ==="

# Configure faster APT mirrors
echo "Configuring APT settings..."
cat > /etc/apt/apt.conf.d/99custom << 'APT_CONF_EOF'
Acquire::Retries "3";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::ftp::Timeout "10";
Acquire::Queue-Mode "access";
Acquire::http::No-Cache "false";
APT_CONF_EOF

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update -q

# Install Qt5 runtime libraries (QBlade v0.96 requires Qt5)
echo "Installing Qt5 and OpenGL dependencies..."
apt-get install -y -q \
    libqt5opengl5 \
    libqt5widgets5 \
    libqt5xml5 \
    libqt5gui5 \
    libqt5core5a \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    mesa-utils \
    libglu1-mesa \
    libegl1 \
    libopengl0

# Install GUI automation and screenshot tools
echo "Installing GUI automation tools..."
apt-get install -y -q \
    xdotool \
    wmctrl \
    scrot \
    x11-utils \
    imagemagick

# Install Python tools for verification
echo "Installing Python verification tools..."
apt-get install -y -q \
    python3-pip \
    python3-dev

# Install download and utility tools
echo "Installing utility tools..."
apt-get install -y -q \
    wget \
    curl \
    unzip \
    jq \
    file

# Create installation directory
INSTALL_DIR="/opt/qblade"
mkdir -p "$INSTALL_DIR"

# Download QBlade CE for Linux
echo "Downloading QBlade CE v0.96 for Linux..."

# Download from SourceForge (stable v0.96 for Linux)
wget --timeout=120 -q -O /tmp/qblade_linux.zip \
    "https://sourceforge.net/projects/qblade/files/QBlade_linux_v0.96.2_64bit.zip/download" || {
    echo "WARNING: Primary download failed, trying fallback..."
    wget --timeout=120 -q -O /tmp/qblade_linux.zip \
        "https://sourceforge.net/projects/qblade/files/QBlade_linux_v09_64bit.zip/download" || {
        echo "ERROR: Failed to download QBlade"
        exit 1
    }
}

# Extract QBlade
echo "Extracting QBlade..."
cd "$INSTALL_DIR"
unzip -o /tmp/qblade_linux.zip -d "$INSTALL_DIR" 2>/dev/null || true

# Find the QBlade binary directory
QBLADE_BIN=$(find "$INSTALL_DIR" -name "QBlade" -type f 2>/dev/null | head -1)
if [ -z "$QBLADE_BIN" ]; then
    echo "WARNING: QBlade binary not found. Listing contents:"
    find "$INSTALL_DIR" -maxdepth 3 -type f | head -30
    exit 1
fi

QBLADE_DIR=$(dirname "$QBLADE_BIN")
echo "Found QBlade binary at: $QBLADE_BIN"

# Fix permissions: make binary and ALL shared libraries readable+executable
chmod 755 "$QBLADE_BIN"
chmod 755 "$QBLADE_DIR"/*.so* 2>/dev/null || true

# Create proper symlinks for bundled shared libraries
cd "$QBLADE_DIR"
ln -sf libQGLViewer.so.2.6.0 libQGLViewer.so.2.6 2>/dev/null || true
ln -sf libQGLViewer.so.2.6.0 libQGLViewer.so.2 2>/dev/null || true
ln -sf libQGLViewer.so.2.6.0 libQGLViewer.so 2>/dev/null || true
ln -sf libgomp.so.1.0.0 libgomp.so.1 2>/dev/null || true

# Remove the bundled libstdc++ as it conflicts with the system one
# (QBlade v0.96 bundles an old libstdc++ from GCC 4.x that breaks modern Qt5)
rm -f "$QBLADE_DIR/libstdc++.so.6" "$QBLADE_DIR/libstdc++.so.6.0.20" 2>/dev/null || true

# Install libQGLViewer to system lib dir so it's always found
cp "$QBLADE_DIR/libQGLViewer.so.2.6.0" /usr/local/lib/
ln -sf /usr/local/lib/libQGLViewer.so.2.6.0 /usr/local/lib/libQGLViewer.so.2
ln -sf /usr/local/lib/libQGLViewer.so.2.6.0 /usr/local/lib/libQGLViewer.so
ldconfig

# Verify library resolution
echo "Verifying library resolution..."
MISSING=$(ldd "$QBLADE_BIN" 2>&1 | grep "not found" || true)
if [ -n "$MISSING" ]; then
    echo "WARNING: Missing libraries:"
    echo "$MISSING"
else
    echo "All libraries resolved successfully"
fi

# Clean up download
rm -f /tmp/qblade_linux.zip

# Copy airfoil data files from workspace to user's home
echo "Setting up data files..."
mkdir -p /home/ga/Documents/airfoils
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/sample_files
mkdir -p /home/ga/Documents/sample_projects
mkdir -p /home/ga/Desktop

# Copy real UIUC airfoil coordinate files
cp /workspace/data/airfoils/*.dat /home/ga/Documents/airfoils/ 2>/dev/null || true

# Copy bundled sample files and projects to user directories
SAMPLE_FILES_DIR=$(find "$INSTALL_DIR" -name "sample files" -type d 2>/dev/null | head -1)
SAMPLE_PROJECTS_DIR=$(find "$INSTALL_DIR" -name "sample projects" -type d 2>/dev/null | head -1)

if [ -n "$SAMPLE_FILES_DIR" ]; then
    cp "$SAMPLE_FILES_DIR"/* /home/ga/Documents/sample_files/ 2>/dev/null || true
    echo "Copied sample files from: $SAMPLE_FILES_DIR"
fi

if [ -n "$SAMPLE_PROJECTS_DIR" ]; then
    cp "$SAMPLE_PROJECTS_DIR"/* /home/ga/Documents/sample_projects/ 2>/dev/null || true
    echo "Copied sample projects from: $SAMPLE_PROJECTS_DIR"
    echo "Sample projects stored in /home/ga/Documents/sample_projects/ (NOT in projects/)"
fi

# Set ownership and permissions
chown -R ga:ga /home/ga/Documents/
chown -R ga:ga /home/ga/Desktop/
find /home/ga/Documents/ -type d -exec chmod 755 {} \;
find /home/ga/Documents/ -type f -exec chmod 644 {} \;

# Verify data
echo "=== Verifying airfoil data files ==="
for f in /home/ga/Documents/airfoils/*.dat; do
    if [ -f "$f" ]; then
        LINES=$(wc -l < "$f")
        echo "  $(basename $f): $LINES coordinate points"
    fi
done

echo "=== Verifying sample projects ==="
for f in /home/ga/Documents/sample_projects/*.wpa; do
    if [ -f "$f" ]; then
        SIZE=$(stat -c%s "$f" 2>/dev/null || echo "0")
        echo "  $(basename $f): $SIZE bytes"
    fi
done

echo "=== QBlade installation complete ==="
