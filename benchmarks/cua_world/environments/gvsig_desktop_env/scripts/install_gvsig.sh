#!/bin/bash
# pre_start hook: Install gvSIG Desktop and download Natural Earth GIS data
# Runs as root before the desktop starts

echo "=== Installing gvSIG Desktop ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install system dependencies - Java is required by gvSIG deb package
echo "Installing system dependencies..."
apt-get install -y \
    wget \
    curl \
    unzip \
    ca-certificates \
    libxrender1 \
    libxtst6 \
    libxi6 \
    libxrandr2 \
    libfreetype6 \
    fontconfig \
    xdotool \
    wmctrl \
    x11-utils \
    imagemagick \
    python3-pip \
    scrot \
    default-jre \
    openjdk-8-jdk

# Install Python GIS libraries for potential verification
pip3 install --no-cache-dir pillow 2>/dev/null || true

# -------------------------------------------------------------------
# Install gvSIG Desktop via OSGeoLive deb (gvSIG 2.4.0, stable)
# The deb installs to /usr/local/lib/gvsig-desktop/2.4.0-2850-2-amd64/
# and creates /usr/local/bin/gvsig-desktop and /usr/bin/gvsig-desktop
# -------------------------------------------------------------------
DEB_URL="http://download.osgeo.org/livedvd/data/gvsig/gvsig-desktop_2.4.0-2850-2_amd64.deb"

echo "Downloading gvSIG Desktop deb package..."
if wget -q --timeout=600 --tries=3 "$DEB_URL" -O /tmp/gvsig.deb; then
    echo "Installing gvSIG 2.4.0 from OSGeoLive deb..."
    dpkg -i /tmp/gvsig.deb || apt-get install -f -y
    rm -f /tmp/gvsig.deb
    echo "gvSIG 2.4.0 deb installed"
else
    echo "ERROR: Could not download gvSIG deb package!"
    exit 1
fi

# The deb creates /usr/local/bin/gvsig-desktop which is the correct launcher.
# DO NOT overwrite it — the deb's launcher correctly points to the install dir.
# The actual gvSIG.sh is at /usr/local/lib/gvsig-desktop/2.4.0-2850-2-amd64/gvSIG.sh

# Save the actual launcher path for setup/task scripts
GVSIG_SH="/usr/local/lib/gvsig-desktop/2.4.0-2850-2-amd64/gvSIG.sh"
if [ -f "$GVSIG_SH" ]; then
    echo "$GVSIG_SH" > /etc/gvsig_launcher_path
    chmod +x "$GVSIG_SH"
    echo "gvSIG launcher confirmed: $GVSIG_SH"
else
    # Try to find it
    FOUND=$(find /usr/local/lib -name "gvSIG.sh" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        echo "$FOUND" > /etc/gvsig_launcher_path
        chmod +x "$FOUND"
        echo "gvSIG launcher found: $FOUND"
    else
        echo "ERROR: gvSIG.sh not found after deb install!"
        exit 1
    fi
fi

# -------------------------------------------------------------------
# Download Natural Earth GIS Data (real public domain datasets)
# Natural Earth: public domain, widely used in GIS education
# -------------------------------------------------------------------
GVSIG_DATA_DIR="/home/ga/gvsig_data"
mkdir -p "$GVSIG_DATA_DIR/countries"
mkdir -p "$GVSIG_DATA_DIR/rivers"
mkdir -p "$GVSIG_DATA_DIR/cities"
mkdir -p "$GVSIG_DATA_DIR/projects"
mkdir -p "$GVSIG_DATA_DIR/exports"

echo "Downloading Natural Earth datasets..."

download_natural_earth() {
    local filename="$1"
    local category="$2"   # "cultural" or "physical"
    local dest_dir="$3"

    local url1="https://naciscdn.org/naturalearth/110m/${category}/${filename}.zip"
    local url2="https://naturalearth.s3.amazonaws.com/110m_${category}/${filename}.zip"

    if wget -q --timeout=120 --tries=3 "$url1" -O /tmp/ne_data.zip; then
        unzip -q -o /tmp/ne_data.zip -d "$dest_dir"
        rm -f /tmp/ne_data.zip
        echo "Downloaded $filename"
    elif wget -q --timeout=120 --tries=3 "$url2" -O /tmp/ne_data.zip; then
        unzip -q -o /tmp/ne_data.zip -d "$dest_dir"
        rm -f /tmp/ne_data.zip
        echo "Downloaded $filename (fallback)"
    else
        echo "WARNING: Could not download $filename"
    fi
}

download_natural_earth "ne_110m_admin_0_countries" "cultural" "$GVSIG_DATA_DIR/countries"
download_natural_earth "ne_110m_rivers_lake_centerlines" "physical" "$GVSIG_DATA_DIR/rivers"
download_natural_earth "ne_110m_populated_places" "cultural" "$GVSIG_DATA_DIR/cities"

# Set permissions — gvSIG needs write access to data directories (creates index files)
chown -R ga:ga "$GVSIG_DATA_DIR"
chmod -R 755 "$GVSIG_DATA_DIR"

# Verify key files
echo "Verifying downloads..."
if ls "$GVSIG_DATA_DIR/countries/"*.shp 2>/dev/null | head -1 | grep -q shp; then
    echo "Countries shapefile: OK"
    ls -lh "$GVSIG_DATA_DIR/countries/"*.shp 2>/dev/null | head -5
else
    echo "WARNING: Countries shapefile not found!"
fi

echo "=== gvSIG Desktop installation complete ==="
