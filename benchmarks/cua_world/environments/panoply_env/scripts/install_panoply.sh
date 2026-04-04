#!/bin/bash
set -e

echo "=== Installing NASA Panoply ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Java (JDK recommended for Panoply)
echo "Installing Java JDK..."
apt-get install -y \
    default-jdk \
    wget \
    curl \
    unzip \
    scrot \
    wmctrl \
    xdotool \
    x11-utils \
    python3-pip \
    python3-venv \
    imagemagick

# Verify Java installation
java -version 2>&1 || { echo "ERROR: Java installation failed"; exit 1; }

# Download Panoply
echo "Downloading NASA Panoply..."
PANOPLY_VERSION="5.3.1"

cd /tmp
DOWNLOADED=false

# Try 1: Official NASA GISS site (multiple versions)
for ver in "5.9.1" "5.7.1" "5.5.4" "5.3.1"; do
    echo "Trying NASA GISS version $ver..."
    if wget -q --timeout=15 "https://www.giss.nasa.gov/tools/panoply/download/PanoplyJ-${ver}.tgz" -O "PanoplyJ.tgz" 2>/dev/null; then
        file PanoplyJ.tgz | grep -q "gzip" && { DOWNLOADED=true; PANOPLY_VERSION="$ver"; echo "Downloaded Panoply $ver from NASA GISS"; break; }
    fi
    rm -f PanoplyJ.tgz
done

# Try 2: Wayback Machine archive (known working)
if [ "$DOWNLOADED" = "false" ]; then
    echo "NASA GISS unreachable, trying Wayback Machine..."
    if wget -q --timeout=60 "https://web.archive.org/web/20240115173241if_/https://www.giss.nasa.gov/tools/panoply/download/PanoplyJ-5.3.1.tgz" -O "PanoplyJ.tgz" 2>/dev/null; then
        file PanoplyJ.tgz | grep -q "gzip" && { DOWNLOADED=true; PANOPLY_VERSION="5.3.1"; echo "Downloaded Panoply 5.3.1 from Wayback Machine"; }
    fi
fi

# Try 3: ZIP from Wayback Machine
if [ "$DOWNLOADED" = "false" ]; then
    echo "Trying ZIP format from Wayback Machine..."
    if wget -q --timeout=60 "https://web.archive.org/web/20240115173245if_/https://www.giss.nasa.gov/tools/panoply/download/PanoplyJ-5.3.1.zip" -O "PanoplyJ.zip" 2>/dev/null; then
        if file PanoplyJ.zip | grep -q "Zip"; then
            unzip -q PanoplyJ.zip -d /tmp/
            DOWNLOADED=true
            PANOPLY_VERSION="5.3.1"
            echo "Downloaded Panoply 5.3.1 ZIP from Wayback Machine"
        fi
    fi
fi

# Verify download
if [ "$DOWNLOADED" = "false" ]; then
    echo "ERROR: Panoply download failed from all sources"
    exit 1
fi

# Extract Panoply (if tgz was downloaded)
if [ -f "PanoplyJ.tgz" ]; then
    echo "Extracting Panoply..."
    tar -xzf PanoplyJ.tgz 2>/dev/null || tar --warning=no-unknown-keyword -xzf PanoplyJ.tgz
fi

# Find extracted directory
PANOPLY_DIR=$(find /tmp -maxdepth 1 -type d -name "PanoplyJ*" | head -1)
if [ -z "$PANOPLY_DIR" ]; then
    echo "ERROR: Could not find extracted Panoply directory"
    ls -la /tmp/
    exit 1
fi

# Install to /opt
echo "Installing Panoply to /opt/PanoplyJ..."
rm -rf /opt/PanoplyJ
mv "$PANOPLY_DIR" /opt/PanoplyJ

# Verify panoply.sh exists
if [ ! -f "/opt/PanoplyJ/panoply.sh" ]; then
    echo "ERROR: panoply.sh not found in /opt/PanoplyJ"
    ls -la /opt/PanoplyJ/
    exit 1
fi

chmod +x /opt/PanoplyJ/panoply.sh

# Create system-wide symlink
ln -sf /opt/PanoplyJ/panoply.sh /usr/local/bin/panoply

# Create desktop entry
cat > /usr/share/applications/panoply.desktop << 'EOF'
[Desktop Entry]
Name=Panoply
GenericName=NetCDF Data Viewer
Comment=View netCDF, HDF, and GRIB data files
Exec=/opt/PanoplyJ/panoply.sh %f
Terminal=false
Type=Application
Categories=Science;Education;
MimeType=application/x-netcdf;application/x-hdf;
EOF

# Download real netCDF data files from NOAA
echo "Downloading real NOAA netCDF data files..."
DATA_DIR="/home/ga/PanoplyData"
mkdir -p "$DATA_DIR"

# Air Temperature monthly long-term mean (NCEP/NCAR Reanalysis, ~642KB)
echo "Downloading NCEP air temperature data..."
wget -q -O "$DATA_DIR/air.mon.ltm.nc" \
    "https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis.derived/surface/air.mon.ltm.nc" || \
    echo "Warning: Could not download air temperature data"

# Sea Surface Temperature long-term mean (NOAA OI SST v2, ~3.4MB)
echo "Downloading NOAA SST data..."
wget -q -O "$DATA_DIR/sst.ltm.1991-2020.nc" \
    "https://downloads.psl.noaa.gov/Datasets/noaa.oisst.v2/sst.ltm.1991-2020.nc" || \
    echo "Warning: Could not download SST data"

# Precipitation rate monthly long-term mean (~709KB)
echo "Downloading NCEP precipitation rate data..."
wget -q -O "$DATA_DIR/prate.sfc.mon.ltm.nc" \
    "https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis.derived/surface_gauss/prate.sfc.mon.ltm.1981-2010.nc" || \
    echo "Warning: Could not download precipitation data"

# Sea Level Pressure monthly long-term mean (~539KB)
echo "Downloading NCEP sea level pressure data..."
wget -q -O "$DATA_DIR/slp.mon.ltm.nc" \
    "https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis.derived/surface/slp.mon.ltm.nc" || \
    echo "Warning: Could not download SLP data"

# Surface Pressure monthly long-term mean (~588KB)
echo "Downloading NCEP surface pressure data..."
wget -q -O "$DATA_DIR/pres.mon.ltm.nc" \
    "https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis.derived/surface/pres.mon.ltm.nc" || \
    echo "Warning: Could not download surface pressure data"

# Set ownership
chown -R ga:ga "$DATA_DIR"

# List downloaded files
echo "Downloaded data files:"
ls -lh "$DATA_DIR/"

# Clean up
rm -f /tmp/PanoplyJ.tgz /tmp/PanoplyJ.zip

# Install Python packages for verification
pip3 install --quiet pillow numpy 2>/dev/null || true

echo "=== NASA Panoply installation complete ==="
echo "Panoply installed at: /opt/PanoplyJ"
echo "Data files at: $DATA_DIR"
