#!/bin/bash
set -e

echo "=== Installing Fiji (ImageJ distribution) and related packages ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package manager
apt-get update

# Install Java (Fiji needs Java)
echo "Installing Java JDK..."
apt-get install -y openjdk-17-jre-headless openjdk-17-jdk-headless

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    scrot \
    imagemagick

# Install Python libraries for image handling
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-numpy \
    python3-scipy \
    python3-pillow \
    python3-pandas

# Install additional Python packages
pip3 install --no-cache-dir --break-system-packages scikit-image || \
    pip3 install --no-cache-dir scikit-image || \
    echo "WARNING: Could not install scikit-image"

# Install file utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    tar \
    curl \
    wget

# Download Fiji (ImageJ with batteries included)
echo "Downloading Fiji..."
FIJI_DIR="/opt/fiji"
mkdir -p "$FIJI_DIR"

cd /tmp

# Download Fiji for Linux 64-bit
FIJI_URL="https://downloads.imagej.net/fiji/latest/fiji-latest-linux64-jdk.zip"

wget --timeout=300 "$FIJI_URL" -O fiji.zip 2>&1 || {
    echo "Could not download Fiji from primary URL, trying UK mirror..."
    wget --timeout=300 "https://downloads.micron.ox.ac.uk/fiji_update/mirrors/fiji-latest/fiji-latest-linux64-jdk.zip" \
        -O fiji.zip 2>&1 || {
        echo "Could not download from UK mirror, trying stable version..."
        wget --timeout=300 "https://downloads.imagej.net/fiji/stable/fiji-stable-linux64-jdk.zip" \
            -O fiji.zip 2>&1 || {
            echo "ERROR: Could not download Fiji"
            exit 1
        }
    }
}

# Extract if download succeeded
if [ -f fiji.zip ] && [ -s fiji.zip ]; then
    echo "Extracting Fiji..."
    unzip -q fiji.zip -d "$FIJI_DIR" 2>&1
    rm -f fiji.zip
    ls -la "$FIJI_DIR/"
fi

# Find and configure Fiji executable
FIJI_EXEC=""
FIJI_SCRIPT=""

# Search for executables in various possible locations
for path in \
    "$FIJI_DIR/Fiji/fiji-linux-x64" \
    "$FIJI_DIR/Fiji/fiji" \
    "$FIJI_DIR/Fiji.app/ImageJ-linux64" \
    "$FIJI_DIR/ImageJ-linux64" \
    "$FIJI_DIR/fiji-linux64"; do
    if [ -f "$path" ]; then
        if [[ "$path" == *"fiji-linux-x64"* ]]; then
            FIJI_EXEC="$path"
        elif [[ "$path" == */fiji ]] && [ -x "$path" ]; then
            FIJI_SCRIPT="$path"
        elif [[ "$path" == *"ImageJ-linux64"* ]]; then
            FIJI_EXEC="$path"
        fi
    fi
done

# Find the native binary (preferred) or shell script
FIJI_LAUNCH=""
FIJI_BASE_DIR=""

if [ -n "$FIJI_EXEC" ]; then
    chmod +x "$FIJI_EXEC"
    FIJI_LAUNCH="$FIJI_EXEC"
    FIJI_BASE_DIR=$(dirname "$FIJI_EXEC")
    echo "Found Fiji native binary: $FIJI_EXEC"
elif [ -n "$FIJI_SCRIPT" ]; then
    chmod +x "$FIJI_SCRIPT"
    FIJI_LAUNCH="$FIJI_SCRIPT"
    FIJI_BASE_DIR=$(dirname "$FIJI_SCRIPT")
    echo "Found Fiji script: $FIJI_SCRIPT"
else
    echo "Error: Could not find Fiji executable"
    find "$FIJI_DIR" -type f \( -name "fiji*" -o -name "ImageJ*" \) 2>/dev/null | head -10
    exit 1
fi

# Create wrapper script
cat > /usr/local/bin/fiji << WRAPPER_EOF
#!/bin/bash
# Fiji launcher wrapper
cd "$FIJI_BASE_DIR" || exit 1
exec "$FIJI_LAUNCH" "\$@"
WRAPPER_EOF
chmod +x /usr/local/bin/fiji

# Also create imagej symlink
cp /usr/local/bin/fiji /usr/local/bin/imagej

echo "Fiji wrapper created at /usr/local/bin/fiji"
echo "  Base directory: $FIJI_BASE_DIR"
echo "  Executable: $FIJI_LAUNCH"

# Set up Fiji.app symlink for compatibility
if [ -d "$FIJI_DIR/Fiji" ] && [ ! -d "$FIJI_DIR/Fiji.app" ]; then
    ln -sf "$FIJI_DIR/Fiji" "$FIJI_DIR/Fiji.app"
    echo "Created Fiji.app symlink for compatibility"
fi

# Set permissions
chmod -R 755 "$FIJI_DIR"

# ============================================================
# Download sample microscopy images
# Using real public datasets from Broad Bioimage Benchmark Collection
# ============================================================
echo "Downloading sample microscopy images..."
SAMPLES_DIR="/opt/fiji_samples"
mkdir -p "$SAMPLES_DIR"
cd "$SAMPLES_DIR"

# Download BBBC (Broad Bioimage Benchmark Collection) sample images
# BBBC005 - Synthetic cells for testing segmentation
echo "Downloading BBBC005 synthetic cell images..."
BBBC_URL="https://data.broadinstitute.org/bbbc/BBBC005/BBBC005_v1_images.zip"
wget -q --timeout=120 "$BBBC_URL" -O bbbc005_images.zip 2>/dev/null || {
    echo "Could not download BBBC005 from primary URL"
}

if [ -f bbbc005_images.zip ] && [ -s bbbc005_images.zip ]; then
    echo "Extracting BBBC005 images..."
    mkdir -p "$SAMPLES_DIR/BBBC005"
    unzip -q bbbc005_images.zip -d "$SAMPLES_DIR/BBBC005" 2>/dev/null || true
    rm -f bbbc005_images.zip
    echo "BBBC005 images extracted to $SAMPLES_DIR/BBBC005"
fi

# Download BBBC005 ground truth
echo "Downloading BBBC005 ground truth..."
BBBC_GT_URL="https://data.broadinstitute.org/bbbc/BBBC005/BBBC005_v1_ground_truth.zip"
wget -q --timeout=60 "$BBBC_GT_URL" -O bbbc005_ground_truth.zip 2>/dev/null || {
    echo "Could not download BBBC005 ground truth"
}

if [ -f bbbc005_ground_truth.zip ] && [ -s bbbc005_ground_truth.zip ]; then
    mkdir -p "$SAMPLES_DIR/BBBC005_ground_truth"
    unzip -q bbbc005_ground_truth.zip -d "$SAMPLES_DIR/BBBC005_ground_truth" 2>/dev/null || true
    rm -f bbbc005_ground_truth.zip
    echo "BBBC005 ground truth extracted"
fi

# Download sample fluorescent cell image from Cell Image Library
echo "Downloading Cell Image Library sample..."
CIL_URL="http://www.cellimagelibrary.org/images/CCDB_2.tif"
wget -q --timeout=60 "$CIL_URL" -O sample_cells.tif 2>/dev/null || {
    echo "Could not download Cell Image Library sample, trying alternative..."
    # Try alternative dataset
    wget -q --timeout=60 "https://imagej.net/images/blobs.gif" -O blobs.gif 2>/dev/null || true
}

# Download a fluorescence microscopy stack from ImageJ sample data
echo "Downloading fluorescence microscopy stack..."
LOCI_URL="https://downloads.openmicroscopy.org/images/DV/will/DAPI_NUC.r3d_D3D.dv"
wget -q --timeout=120 "$LOCI_URL" -O fluorescence_stack.dv 2>/dev/null || {
    echo "Could not download fluorescence stack"
}

# Set permissions on samples
chmod -R 755 "$SAMPLES_DIR"

# Create sample image workspace
echo "Creating sample image workspace..."
mkdir -p /opt/fiji_samples/workspace
chmod -R 755 /opt/fiji_samples

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Fiji installation completed ==="
echo "Fiji location: $FIJI_DIR"
echo "Sample images location: $SAMPLES_DIR"
echo ""
echo "Fiji can be launched with: fiji or imagej"
