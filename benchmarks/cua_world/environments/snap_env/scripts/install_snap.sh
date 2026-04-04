#!/bin/bash
set -e

echo "=== Installing ESA SNAP (Sentinel Application Platform) ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install core dependencies
apt-get install -y \
    wget \
    curl \
    ca-certificates \
    gnupg \
    unzip \
    libgfortran5 \
    libgomp1

# Install GUI automation tools
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    scrot \
    imagemagick

# Install Python tools
apt-get install -y \
    python3-pip \
    python3-dev

pip3 install --no-cache-dir pillow

# Download ESA SNAP installer (Sentinel Toolboxes - includes S1TBX, S2TBX, S3TBX)
echo "=== Downloading SNAP installer ==="
SNAP_INSTALLER="/tmp/esa-snap_sentinel_linux.sh"
wget -q --timeout=120 --tries=3 \
    "https://download.esa.int/step/snap/13.0/installers/esa-snap_sentinel_linux-13.0.0.sh" \
    -O "$SNAP_INSTALLER" || \
wget -q --timeout=120 --tries=3 \
    "https://step.esa.int/downloads/13.0/installers/esa-snap_sentinel_linux-13.0.0.sh" \
    -O "$SNAP_INSTALLER"

chmod +x "$SNAP_INSTALLER"

# Create response varfile for unattended installation
cat > /tmp/snap_response.varfile << 'VAREOF'
deleteAllSnapEngineDir$Boolean=false
deleteOnlySnapDesktopDir$Boolean=true
executeLauncherWithPythonAction$Boolean=false
forcePython$Boolean=false
pythonExecutable=/usr/bin/python3
sys.adminRights$Boolean=true
sys.component.RSTB$Boolean=true
sys.component.S1TBX$Boolean=true
sys.component.S2TBX$Boolean=true
sys.component.S3TBX$Boolean=true
sys.component.SNAP$Boolean=true
sys.installationDir=/opt/snap
sys.languageId=en
sys.programGroupDisabled$Boolean=true
sys.symlinkDir=/usr/local/bin/snap-esa
VAREOF

# Install SNAP in unattended mode
echo "=== Running SNAP installer (unattended) ==="
bash "$SNAP_INSTALLER" -q -varfile /tmp/snap_response.varfile

# Create symlinks that don't conflict with Ubuntu's snap package manager
if [ -f /opt/snap/bin/snap ]; then
    ln -sf /opt/snap/bin/snap /usr/local/bin/esa-snap
fi
if [ -f /opt/snap/bin/gpt ]; then
    ln -sf /opt/snap/bin/gpt /usr/local/bin/snap-gpt
fi

# Verify installation
echo "=== Verifying SNAP installation ==="
if [ -d /opt/snap ]; then
    echo "SNAP installation directory exists"
    ls -la /opt/snap/bin/
else
    echo "ERROR: SNAP installation directory not found"
    exit 1
fi

if [ -f /opt/snap/bin/snap ]; then
    echo "SNAP executable found"
else
    echo "ERROR: SNAP executable not found"
    exit 1
fi

if [ -f /opt/snap/bin/gpt ]; then
    echo "GPT (Graph Processing Tool) found"
else
    echo "WARNING: GPT not found"
fi

# Download real satellite data for tasks
echo "=== Downloading real satellite data ==="
DATA_DIR="/home/ga/snap_data"
mkdir -p "$DATA_DIR"

# 1. Sentinel-2A multi-band GeoTIFF (real Copernicus data, 3 bands, ~5.7MB)
echo "Downloading Sentinel-2A sample GeoTIFF..."
wget -q --timeout=60 --tries=3 \
    "https://raw.githubusercontent.com/mommermi/geotiff_sample/master/sample.tif" \
    -O "$DATA_DIR/sentinel2a_sample.tif" || echo "WARNING: Failed to download sentinel2a_sample.tif"

# 2. Sentinel-2 B4,B3,B2 bands (real Sentinel-2 RGB bands, ~2.1MB)
echo "Downloading Sentinel-2 RGB bands..."
wget -q --timeout=60 --tries=3 \
    "https://raw.githubusercontent.com/leftfield-geospatial/homonim/main/tests/data/reference/sentinel2_b432_byte.tif" \
    -O "$DATA_DIR/sentinel2_b432.tif" || echo "WARNING: Failed to download sentinel2_b432.tif"

# 3. Landsat multi-band GeoTIFF (4 bands: SWIR1, NIR, Red, Green, ~9.7MB)
echo "Downloading Landsat multi-band GeoTIFF..."
wget -q --timeout=60 --tries=3 \
    "https://raw.githubusercontent.com/opengeos/data/main/raster/landsat.tif" \
    -O "$DATA_DIR/landsat_multispectral.tif" || echo "WARNING: Failed to download landsat.tif"

# 4. Sentinel-2 True Color Image from AWS COGs (real Sentinel-2 L2A, ~12MB)
echo "Downloading Sentinel-2 True Color Image..."
wget -q --timeout=120 --tries=3 \
    "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/TCI.tif" \
    -O "$DATA_DIR/sentinel2_tci.tif" || echo "WARNING: Failed to download TCI.tif"

# 5. Sentinel-2 individual bands for NDVI computation (B04=Red, B08=NIR)
echo "Downloading Sentinel-2 Red band (B04)..."
wget -q --timeout=120 --tries=3 \
    "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B04.tif" \
    -O "$DATA_DIR/sentinel2_B04_red.tif" || echo "WARNING: Failed to download B04.tif"

echo "Downloading Sentinel-2 NIR band (B08)..."
wget -q --timeout=120 --tries=3 \
    "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/31/T/GM/2020/12/S2A_31TGM_20201223_0_L2A/B08.tif" \
    -O "$DATA_DIR/sentinel2_B08_nir.tif" || echo "WARNING: Failed to download B08.tif"

# 6. DEM data for terrain tasks
echo "Downloading SRTM DEM..."
wget -q --timeout=60 --tries=3 \
    "https://raw.githubusercontent.com/opengeos/data/main/raster/dem.tif" \
    -O "$DATA_DIR/srtm_dem.tif" || echo "WARNING: Failed to download dem.tif"

# 7. Landsat 7 RGB for visual tasks
echo "Downloading Landsat 7 RGB..."
wget -q --timeout=60 --tries=3 \
    "https://raw.githubusercontent.com/rasterio/rasterio/main/tests/data/RGB.byte.tif" \
    -O "$DATA_DIR/landsat7_rgb.tif" || echo "WARNING: Failed to download RGB.byte.tif"

# Set ownership
chown -R ga:ga "$DATA_DIR"

# List downloaded data
echo "=== Downloaded satellite data ==="
ls -lh "$DATA_DIR/"

# Clean up
rm -f "$SNAP_INSTALLER" /tmp/snap_response.varfile
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== SNAP installation complete ==="
