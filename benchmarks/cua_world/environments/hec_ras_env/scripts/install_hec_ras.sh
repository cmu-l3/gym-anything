#!/bin/bash
set -e

echo "=== Installing HEC-RAS 6.6 Linux Compute Engines ==="

export DEBIAN_FRONTEND=noninteractive

# --- 1. Update package lists and install dependencies ---
echo "--- Installing system dependencies ---"
apt-get update
apt-get install -y \
    wget curl unzip \
    xdotool wmctrl scrot imagemagick x11-utils xclip \
    python3 python3-pip python3-venv \
    gedit gnome-terminal dbus-x11 \
    libgomp1 libgfortran5 \
    bc file

# --- 2. Install Python packages for HEC-RAS data analysis ---
echo "--- Installing Python packages ---"
pip3 install --break-system-packages \
    h5py numpy matplotlib pandas scipy \
    rashdf 2>/dev/null || \
pip3 install \
    h5py numpy matplotlib pandas scipy \
    rashdf 2>/dev/null || true

# --- 3. Download HEC-RAS 6.6 Linux build ---
echo "--- Downloading HEC-RAS 6.6 Linux build ---"
HECRAS_DIR="/opt/hec-ras"
mkdir -p "$HECRAS_DIR"
cd /tmp

# Primary URL
HECRAS_URL="https://www.hec.usace.army.mil/software/hec-ras/downloads/Linux_RAS_v66.zip"
HECRAS_ZIP="/tmp/Linux_RAS_v66.zip"

if ! wget -q --timeout=120 --tries=3 -O "$HECRAS_ZIP" "$HECRAS_URL" 2>/dev/null; then
    echo "Primary URL failed, trying GitHub mirror..."
    HECRAS_URL="https://github.com/HydrologicEngineeringCenter/hec-downloads/releases/download/1.0.33/HEC-RAS_66_Linux.zip"
    if ! wget -q --timeout=120 --tries=3 -O "$HECRAS_ZIP" "$HECRAS_URL" 2>/dev/null; then
        echo "WARNING: Could not download HEC-RAS. Trying alternate approach..."
        # Try 6.5 as fallback
        HECRAS_URL="https://www.hec.usace.army.mil/software/hec-ras/downloads/Linux_RAS_v65.zip"
        wget -q --timeout=120 --tries=3 -O "$HECRAS_ZIP" "$HECRAS_URL" 2>/dev/null || true
    fi
fi

if [ -f "$HECRAS_ZIP" ] && [ -s "$HECRAS_ZIP" ]; then
    echo "--- Extracting HEC-RAS ---"
    cd "$HECRAS_DIR"
    unzip -o "$HECRAS_ZIP" -d "$HECRAS_DIR"

    # Find and extract the inner zip (RAS_Linux_test_setup.zip)
    INNER_ZIP=$(find "$HECRAS_DIR" -name "RAS_Linux_test_setup.zip" -o -name "*.zip" | head -1)
    if [ -n "$INNER_ZIP" ] && [ -f "$INNER_ZIP" ]; then
        echo "--- Extracting inner setup archive: $INNER_ZIP ---"
        unzip -o "$INNER_ZIP" -d "$HECRAS_DIR"
    fi

    # Find executables directory
    BIN_DIR=""
    for d in "$HECRAS_DIR"/RAS_Linux_test_setup/Ras_v*/Release \
             "$HECRAS_DIR"/Ras_v*/Release \
             "$HECRAS_DIR"/Release; do
        if [ -d "$d" ]; then
            BIN_DIR="$d"
            break
        fi
    done

    if [ -z "$BIN_DIR" ]; then
        # Search for executables
        BIN_DIR=$(find "$HECRAS_DIR" -name "RasUnsteady" -type f -exec dirname {} \; | head -1)
    fi

    if [ -n "$BIN_DIR" ]; then
        echo "--- Setting up HEC-RAS binaries from $BIN_DIR ---"
        mkdir -p "$HECRAS_DIR/bin"
        cp "$BIN_DIR"/* "$HECRAS_DIR/bin/" 2>/dev/null || true
        chmod +x "$HECRAS_DIR/bin"/*
    fi

    # Find and setup libraries
    LIB_DIR=""
    for d in "$HECRAS_DIR"/Linux_RAS_v66/libs \
             "$HECRAS_DIR"/Linux_RAS_v65/libs \
             "$HECRAS_DIR"/RAS_Linux_test_setup/libs \
             "$HECRAS_DIR"/libs; do
        if [ -d "$d" ]; then
            LIB_DIR="$d"
            break
        fi
    done

    if [ -z "$LIB_DIR" ]; then
        LIB_DIR=$(find "$HECRAS_DIR" -name "libiomp5.so" -type f -exec dirname {} \; | head -1)
    fi

    if [ -n "$LIB_DIR" ]; then
        echo "--- Setting up HEC-RAS libraries from $LIB_DIR ---"
        mkdir -p "$HECRAS_DIR/lib"
        cp -r "$LIB_DIR"/* "$HECRAS_DIR/lib/"
        chmod 755 "$HECRAS_DIR/lib"/*.so* 2>/dev/null || true
        # Handle subdirectories (mkl, rhel_8)
        for subdir in "$HECRAS_DIR/lib"/*/; do
            if [ -d "$subdir" ]; then
                chmod 755 "$subdir"/*.so* 2>/dev/null || true
            fi
        done
    fi

    # Setup Muncie example project
    MUNCIE_SRC=""
    for d in "$HECRAS_DIR"/Linux_RAS_v66/Muncie \
             "$HECRAS_DIR"/Linux_RAS_v65/Muncie \
             "$HECRAS_DIR"/RAS_Linux_test_setup/Muncie \
             "$HECRAS_DIR"/Muncie; do
        if [ -d "$d" ]; then
            MUNCIE_SRC="$d"
            break
        fi
    done

    if [ -z "$MUNCIE_SRC" ]; then
        MUNCIE_SRC=$(find "$HECRAS_DIR" -name "Muncie" -type d | head -1)
    fi

    if [ -n "$MUNCIE_SRC" ]; then
        echo "--- Found Muncie example project at $MUNCIE_SRC ---"
        mkdir -p "$HECRAS_DIR/examples/Muncie"
        cp -r "$MUNCIE_SRC"/* "$HECRAS_DIR/examples/Muncie/"
        # Also copy the wrk_source files to the main directory for easier access
        if [ -d "$MUNCIE_SRC/wrk_source" ]; then
            cp "$MUNCIE_SRC/wrk_source"/* "$HECRAS_DIR/examples/Muncie/" 2>/dev/null || true
        fi
    fi

    rm -f "$HECRAS_ZIP"
else
    echo "ERROR: HEC-RAS download failed"
fi

# --- 4. Create environment profile script ---
echo "--- Creating HEC-RAS environment profile ---"
cat > /etc/profile.d/hec-ras.sh << 'PROFILE_EOF'
export HECRAS_HOME="/opt/hec-ras"
export PATH="$HECRAS_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$HECRAS_HOME/lib:$HECRAS_HOME/lib/mkl:$HECRAS_HOME/lib/rhel_8:$LD_LIBRARY_PATH"
PROFILE_EOF
chmod +x /etc/profile.d/hec-ras.sh

# --- 5. Verify installation ---
echo "--- Verifying HEC-RAS installation ---"
echo "HEC-RAS directory contents:"
ls -la "$HECRAS_DIR/" 2>/dev/null || echo "  (directory not found)"
echo "Binaries:"
ls -la "$HECRAS_DIR/bin/" 2>/dev/null || echo "  (bin directory not found)"
echo "Libraries:"
ls "$HECRAS_DIR/lib/" 2>/dev/null | head -20 || echo "  (lib directory not found)"
echo "Muncie example:"
ls "$HECRAS_DIR/examples/Muncie/" 2>/dev/null || echo "  (Muncie not found)"

# Check if key executables exist
for exe in RasUnsteady RasSteady RasGeomPreprocess; do
    if [ -f "$HECRAS_DIR/bin/$exe" ]; then
        echo "  FOUND: $exe"
    else
        echo "  MISSING: $exe"
    fi
done

# --- 6. Copy analysis scripts ---
echo "--- Copying analysis scripts ---"
mkdir -p /opt/hec-ras/analysis_scripts
cp /workspace/data/analysis_scripts/*.py /opt/hec-ras/analysis_scripts/ 2>/dev/null || true
chmod +x /opt/hec-ras/analysis_scripts/*.py 2>/dev/null || true

echo "=== HEC-RAS installation complete ==="
