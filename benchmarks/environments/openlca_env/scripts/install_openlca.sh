#!/bin/bash
# set -euo pipefail

echo "=== Installing OpenLCA and related packages ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package manager
apt-get update

# Install Java 21 (OpenLCA 2.x bundles its own JRE, but we need JDK for tools)
echo "Installing Java JDK..."
apt-get install -y openjdk-21-jre-headless 2>/dev/null || \
    apt-get install -y openjdk-17-jre-headless 2>/dev/null || \
    echo "WARNING: Could not install Java JDK, OpenLCA bundles its own"

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    scrot \
    imagemagick

# Install Python libraries
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-numpy

# Install file utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    tar \
    curl \
    wget \
    jq \
    xmlstarlet

# Install gfortran for high-performance calculations in OpenLCA
echo "Installing gfortran for OpenLCA calculations..."
apt-get install -y gfortran 2>/dev/null || echo "WARNING: gfortran not available"

# ============================================================
# Download OpenLCA
# ============================================================
echo "Downloading OpenLCA..."
OPENLCA_DIR="/opt/openlca"
mkdir -p "$OPENLCA_DIR"

cd /tmp

# OpenLCA 2.x binaries are hosted on GreenDelta's Nextcloud share
# at share.greendelta.com (NOT on SourceForge or GitHub releases)
OPENLCA_DOWNLOADED=false

# Method 1: Download OpenLCA 2.6.0 from GreenDelta Nextcloud (primary)
echo "Attempting to download OpenLCA 2.6.0 from GreenDelta..."
wget --timeout=600 --tries=3 -q --show-progress \
    -O /tmp/openlca.tar.gz \
    'https://share.greendelta.com/index.php/s/D1xa3haTiHJdhqt/download?path=%2F2.6.0&files=openLCA_mkl_Linux_x64_2.6.0_2025-12-15.tar.gz' 2>&1 && \
    OPENLCA_DOWNLOADED=true || true

# Method 2: Try OpenLCA 2.5.0 if 2.6.0 failed
if [ "$OPENLCA_DOWNLOADED" = false ] || [ ! -s /tmp/openlca.tar.gz ]; then
    echo "Trying OpenLCA 2.5.0..."
    wget --timeout=600 --tries=3 -q --show-progress \
        -O /tmp/openlca.tar.gz \
        'https://share.greendelta.com/index.php/s/D1xa3haTiHJdhqt/download?path=%2F2.5.0&files=openLCA_mkl_Linux_x64_2.5.0_2025-07-07.tar.gz' 2>&1 && \
        OPENLCA_DOWNLOADED=true || true
fi

# Method 3: Try OpenLCA 2.4.0 as further fallback
if [ "$OPENLCA_DOWNLOADED" = false ] || [ ! -s /tmp/openlca.tar.gz ]; then
    echo "Trying OpenLCA 2.4.0..."
    wget --timeout=600 --tries=3 -q --show-progress \
        -O /tmp/openlca.tar.gz \
        'https://share.greendelta.com/index.php/s/D1xa3haTiHJdhqt/download?path=%2F2.4.0&files=openLCA_mkl_Linux_x64_2.4.0_2025-03-07.tar.gz' 2>&1 && \
        OPENLCA_DOWNLOADED=true || true
fi

# Method 4: Try curl if wget failed (sometimes handles Nextcloud better)
if [ "$OPENLCA_DOWNLOADED" = false ] || [ ! -s /tmp/openlca.tar.gz ]; then
    echo "Trying curl for OpenLCA 2.6.0..."
    curl -L --max-time 600 --retry 3 -o /tmp/openlca.tar.gz \
        'https://share.greendelta.com/index.php/s/D1xa3haTiHJdhqt/download?path=%2F2.6.0&files=openLCA_mkl_Linux_x64_2.6.0_2025-12-15.tar.gz' 2>&1 && \
        OPENLCA_DOWNLOADED=true || true
fi

# Method 5: Last resort - try SourceForge for OpenLCA 1.9.0 (only 1.x available there)
if [ "$OPENLCA_DOWNLOADED" = false ] || [ ! -s /tmp/openlca.tar.gz ]; then
    echo "Trying SourceForge fallback for OpenLCA 1.9.0..."
    curl -L --max-time 300 --retry 3 -o /tmp/openlca.tar.gz \
        'https://sourceforge.net/projects/openlca/files/openlca_framework/1.9/openLCA_linux64_1.9.0_2019-06-28.tar.gz/download' 2>&1 && \
        OPENLCA_DOWNLOADED=true || true
fi

# Extract if download succeeded
if [ -f /tmp/openlca.tar.gz ] && [ -s /tmp/openlca.tar.gz ]; then
    echo "Extracting OpenLCA..."
    # Verify the file is actually a gzip/tar archive (not an HTML error page)
    FILE_TYPE=$(file /tmp/openlca.tar.gz | head -1)
    if echo "$FILE_TYPE" | grep -qi "gzip\|tar\|XZ"; then
        tar -xzf /tmp/openlca.tar.gz -C "$OPENLCA_DIR" 2>&1 || \
            tar -xf /tmp/openlca.tar.gz -C "$OPENLCA_DIR" 2>&1
        echo "Extraction successful"
    else
        echo "Downloaded file is not a valid archive: $FILE_TYPE"
        rm -f /tmp/openlca.tar.gz
    fi
    rm -f /tmp/openlca.tar.gz
else
    echo "WARNING: All OpenLCA download attempts failed"
fi

# Find and link the OpenLCA executable
# OpenLCA 2.x extracts to a directory like openLCA/ with the binary named "openLCA"
echo "Searching for OpenLCA executable..."
echo "Contents of $OPENLCA_DIR:"
ls -la "$OPENLCA_DIR/" 2>/dev/null
find "$OPENLCA_DIR" -maxdepth 3 -type f -name "openLCA*" 2>/dev/null | head -20

OPENLCA_EXEC=""
# Check common subdirectory patterns for OpenLCA 2.x
for subdir in "openLCA" "openlca" "openLCA_linux64" "openLCA-2" "" \
              "openLCA_mkl_Linux_x64" "openLCA_Linux_x64" "openLCA-1.9" "openLCA-1.11"; do
    for binpath in "openLCA" "openlca" "openLCA.sh" "openlca.sh"; do
        testpath="$OPENLCA_DIR/$subdir/$binpath"
        if [ -f "$testpath" ]; then
            OPENLCA_EXEC="$testpath"
            break 2
        fi
    done
done

if [ -z "$OPENLCA_EXEC" ]; then
    # Search recursively for the executable
    OPENLCA_EXEC=$(find "$OPENLCA_DIR" -maxdepth 4 -type f \( -name "openLCA" -o -name "openlca" -o -name "openLCA.sh" \) 2>/dev/null | head -1)
fi

if [ -n "$OPENLCA_EXEC" ]; then
    chmod +x "$OPENLCA_EXEC"
    ln -sf "$OPENLCA_EXEC" /usr/local/bin/openlca
    echo "OpenLCA executable found and linked: $OPENLCA_EXEC"
    # Also make all .so files and jre executable
    OPENLCA_BASE=$(dirname "$OPENLCA_EXEC")
    find "$OPENLCA_BASE" -name "*.so" -exec chmod +x {} \; 2>/dev/null || true
    find "$OPENLCA_BASE" -path "*/jre/bin/*" -exec chmod +x {} \; 2>/dev/null || true
    # Store the base directory for later use
    echo "$OPENLCA_BASE" > /opt/openlca_base_dir.txt
else
    echo "WARNING: Could not find OpenLCA executable after extraction"
    echo "Full directory listing:"
    find "$OPENLCA_DIR" -maxdepth 4 2>/dev/null | head -40
fi

# List what was installed
echo "OpenLCA installation directory contents:"
ls -la "$OPENLCA_DIR/" 2>/dev/null || echo "Directory not found"

# ============================================================
# Download USLCI Database (real LCA data from NREL)
# This is the U.S. Life Cycle Inventory Database — real production data
# ============================================================
echo "Downloading USLCI Database (real LCA data from NREL)..."
DATA_DIR="/opt/openlca_data"
mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

# Download USLCI FY24 Q4 release in JSON-LD format from GitHub
# This is the real, publicly available U.S. LCI database
USLCI_URL="https://github.com/FLCAC-admin/uslci-content/raw/dev/downloads/uslci_fy24_q4_01_olca2_4_0_elci_lib_json_ld.zip"
echo "Downloading USLCI FY24 Q4 JSON-LD database..."
wget --timeout=300 --tries=3 -q --show-progress \
    "$USLCI_URL" \
    -O "$DATA_DIR/uslci_database.zip" 2>&1 || {
    echo "Trying alternative USLCI release..."
    # Try FY25 Q1
    wget --timeout=300 --tries=3 -q --show-progress \
        "https://github.com/FLCAC-admin/uslci-content/raw/dev/downloads/uslci_fy25_q1_01_olca2_4_1_elci_lib_json_ld.zip" \
        -O "$DATA_DIR/uslci_database.zip" 2>&1 || {
        echo "WARNING: Could not download USLCI database"
    }
}

# Verify download
if [ -f "$DATA_DIR/uslci_database.zip" ]; then
    FILESIZE=$(stat -c%s "$DATA_DIR/uslci_database.zip" 2>/dev/null || echo "0")
    if [ "$FILESIZE" -gt 1000000 ]; then
        echo "USLCI database downloaded successfully ($(du -h "$DATA_DIR/uslci_database.zip" | cut -f1))"
    else
        echo "WARNING: USLCI download file seems too small ($FILESIZE bytes), may be incomplete"
        rm -f "$DATA_DIR/uslci_database.zip"
    fi
fi

# ============================================================
# Download LCIA methods pack (TRACI v2.1 for FEDEFL flows)
# These methods are compatible with USLCI databases from FLCAC
# Source: Figshare ndownloader (Ag Data Commons dataset 25782786)
# NOTE: agdatacommons.nal.usda.gov is behind AWS WAF that blocks
#       wget/curl. Use ndownloader.figshare.com which redirects
#       to a presigned S3 URL. curl -L handles this correctly.
# ============================================================
echo "Downloading LCIA methods (TRACI v2.1 for FEDEFL)..."

LCIA_DOWNLOADED=false

# Method 1: TRACI v2.1 from Figshare ndownloader (8.4MB)
echo "Downloading TRACI v2.1 from Figshare..."
curl -L --max-time 180 --retry 3 -o "$DATA_DIR/lcia_methods.zip" \
    "https://ndownloader.figshare.com/files/46211520" 2>&1 && \
    LCIA_DOWNLOADED=true || true

# Method 2: Try ReCiPe 2016 Midpoint I (smaller, 8.9MB) as fallback
if [ "$LCIA_DOWNLOADED" = false ] || [ ! -s "$DATA_DIR/lcia_methods.zip" ]; then
    echo "Trying ReCiPe 2016 Midpoint from Figshare..."
    curl -L --max-time 180 --retry 3 -o "$DATA_DIR/lcia_methods.zip" \
        "https://ndownloader.figshare.com/files/46383358" 2>&1 && \
        LCIA_DOWNLOADED=true || true
fi

# Method 3: Resolve via Figshare API (handles URL changes)
if [ "$LCIA_DOWNLOADED" = false ] || [ ! -s "$DATA_DIR/lcia_methods.zip" ]; then
    echo "Trying Figshare API for TRACI download URL..."
    TRACI_URL=$(curl -s "https://api.figshare.com/v2/articles/25782786" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d['files'][0]['download_url'])" 2>/dev/null || echo "")
    if [ -n "$TRACI_URL" ]; then
        curl -L --max-time 180 --retry 3 -o "$DATA_DIR/lcia_methods.zip" "$TRACI_URL" 2>&1 && \
            LCIA_DOWNLOADED=true || true
    fi
fi

# Validate LCIA download - must be a real zip file, not empty or error page
if [ -f "$DATA_DIR/lcia_methods.zip" ]; then
    LCIA_SIZE=$(stat -c%s "$DATA_DIR/lcia_methods.zip" 2>/dev/null || echo "0")
    if [ "$LCIA_SIZE" -lt 100000 ]; then
        echo "WARNING: LCIA methods file too small ($LCIA_SIZE bytes), removing"
        rm -f "$DATA_DIR/lcia_methods.zip"
        LCIA_DOWNLOADED=false
    else
        FILE_TYPE=$(file "$DATA_DIR/lcia_methods.zip" | head -1)
        if echo "$FILE_TYPE" | grep -qi "zip\|Zip"; then
            echo "LCIA methods downloaded successfully ($(du -h "$DATA_DIR/lcia_methods.zip" | cut -f1))"
        else
            echo "WARNING: LCIA methods file is not a valid zip: $FILE_TYPE"
            rm -f "$DATA_DIR/lcia_methods.zip"
            LCIA_DOWNLOADED=false
        fi
    fi
fi

if [ "$LCIA_DOWNLOADED" = false ]; then
    echo "WARNING: Could not download LCIA methods. Agent will need to use whatever methods are available in openLCA."
fi

# Set permissions
chmod -R 755 "$DATA_DIR" 2>/dev/null || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== OpenLCA installation completed ==="
echo "OpenLCA location: $OPENLCA_DIR"
echo "Data location: $DATA_DIR"
echo ""
echo "Available data files:"
ls -la "$DATA_DIR/" 2>/dev/null || echo "No data files"
