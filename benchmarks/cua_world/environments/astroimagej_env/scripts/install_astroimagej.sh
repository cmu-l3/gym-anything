#!/bin/bash
# set -euo pipefail

echo "=== Installing AstroImageJ and related packages ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package manager
apt-get update

# Install Java (AstroImageJ needs Java)
echo "Installing Java JDK..."
apt-get install -y openjdk-17-jre-headless

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    scrot \
    imagemagick

# Install Python libraries for FITS handling
echo "Installing Python libraries..."
apt-get install -y \
    python3-pip \
    python3-numpy \
    python3-scipy

# Install astropy robustly
echo "Installing astropy..."
pip3 install --no-cache-dir --break-system-packages astropy 2>/dev/null || \
    pip3 install --no-cache-dir astropy 2>/dev/null || \
    apt-get install -y python3-astropy 2>/dev/null || \
    echo "WARNING: Could not install astropy"

# Verify astropy is installed
python3 -c "import astropy; print(f'Astropy version: {astropy.__version__}')" || \
    echo "WARNING: Astropy not available"

# Install file utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    tar \
    curl \
    wget

# Download AstroImageJ
echo "Downloading AstroImageJ..."
AIJ_VERSION="6.0.3.00"
AIJ_DIR="/opt/astroimagej"
mkdir -p "$AIJ_DIR"

# Download AstroImageJ for Linux x64 from GitHub releases
cd /tmp

# Download the latest version from GitHub
wget --timeout=120 "https://github.com/AstroImageJ/astroimagej/releases/download/${AIJ_VERSION}/AstroImageJ-${AIJ_VERSION}-linux-x64.tgz" \
    -O astroimagej.tgz 2>&1 || {
    echo "Could not download AstroImageJ v${AIJ_VERSION}, trying older version..."
    wget --timeout=120 "https://github.com/AstroImageJ/astroimagej/releases/download/6.0.0.00/AstroImageJ-6.0.0.00-linux-x64.tgz" \
        -O astroimagej.tgz 2>&1 || {
        echo "Could not download AstroImageJ, creating placeholder"
        mkdir -p "$AIJ_DIR/AstroImageJ"
        cat > "$AIJ_DIR/AstroImageJ/AstroImageJ" << 'PLACEHOLDER'
#!/bin/bash
echo "AstroImageJ placeholder - download failed during installation"
echo "You can manually install AstroImageJ by downloading from:"
echo "https://astroimagej.com/downloads/"
PLACEHOLDER
        chmod +x "$AIJ_DIR/AstroImageJ/AstroImageJ"
    }
}

# Extract if download succeeded
if [ -f astroimagej.tgz ] && [ -s astroimagej.tgz ]; then
    echo "Extracting AstroImageJ..."
    tar -xzf astroimagej.tgz -C "$AIJ_DIR" 2>&1
    rm -f astroimagej.tgz
    # List what was extracted
    ls -la "$AIJ_DIR/"
fi

# Find and make executable - check multiple possible directory names
AIJ_EXEC=""
for subdir in "astroimagej" "AstroImageJ" ""; do
    for binpath in "bin/AstroImageJ" "AstroImageJ" "bin/aij" "aij"; do
        testpath="$AIJ_DIR/$subdir/$binpath"
        if [ -f "$testpath" ]; then
            AIJ_EXEC="$testpath"
            break 2
        fi
    done
done

if [ -n "$AIJ_EXEC" ]; then
    chmod +x "$AIJ_EXEC"
    ln -sf "$AIJ_EXEC" /usr/local/bin/aij
    echo "AstroImageJ executable found and linked: $AIJ_EXEC"
else
    echo "Warning: Could not find AstroImageJ executable"
    echo "Searching in $AIJ_DIR:"
    find "$AIJ_DIR" -type f \( -name "AstroImageJ" -o -name "aij" \) 2>/dev/null | head -5
fi

# Download sample FITS files from NASA
echo "Downloading sample FITS files..."
FITS_DIR="/opt/fits_samples"
mkdir -p "$FITS_DIR"
cd "$FITS_DIR"

# Download with timeout
wget -q --timeout=30 "https://fits.gsfc.nasa.gov/samples/WFPC2u5780205r_c0fx.fits" \
    -O hst_wfpc2_sample.fits 2>/dev/null || echo "Could not download HST sample"

wget -q --timeout=30 "https://fits.gsfc.nasa.gov/samples/UITfuv2582gc.fits" \
    -O uit_galaxy_sample.fits 2>/dev/null || echo "Could not download UIT sample"

# Set permissions
chmod -R 755 "$FITS_DIR"

# ============================================================
# Download real WASP-12b transit data from University of Louisville
# This is cached at install time to avoid re-downloading 4.3GB each run
# ============================================================
echo "Downloading real WASP-12b transit data from University of Louisville..."
WASP12_DATA_URL="https://www.astro.louisville.edu/software/astroimagej/examples/WASP-12b_example_calibrated_images.tar.gz"
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

mkdir -p /opt/fits_samples

if [ ! -f "$WASP12_CACHE" ]; then
    echo "Downloading WASP-12b calibrated images (4.3GB - this will take a while)..."
    wget -q --show-progress "$WASP12_DATA_URL" -O "$WASP12_CACHE" 2>&1 || {
        echo "WARNING: Could not download WASP-12b data"
        echo "The data will be downloaded during task setup instead"
    }
else
    echo "WASP-12b data already cached"
fi

# Verify download
if [ -f "$WASP12_CACHE" ]; then
    FILESIZE=$(stat -c%s "$WASP12_CACHE" 2>/dev/null || echo "0")
    if [ "$FILESIZE" -gt 1000000000 ]; then
        echo "WASP-12b data cached successfully ($(du -h "$WASP12_CACHE" | cut -f1))"
    else
        echo "WARNING: Downloaded file seems too small, removing..."
        rm -f "$WASP12_CACHE"
    fi
fi

# ============================================================
# Download real Palomar LFC CCD calibration frames from Zenodo
# (Astropy CCD Reduction Guide dataset - 162 MB)
# Used by: calibrate_science_frames task
# ============================================================
echo "Downloading real Palomar LFC CCD calibration data from Zenodo..."
LFC_CACHE="/opt/fits_samples/palomar_lfc.tar.bz2"
LFC_DIR="/opt/fits_samples/palomar_lfc"

if [ ! -d "$LFC_DIR" ]; then
    if [ ! -f "$LFC_CACHE" ]; then
        echo "Downloading Palomar LFC data (162 MB)..."
        wget -q --show-progress --timeout=120 \
            "https://zenodo.org/records/3254683/files/example-cryo-LFC.tar.bz2?download=1" \
            -O "$LFC_CACHE" 2>&1 || {
            echo "WARNING: Could not download Palomar LFC data"
        }
    fi
    if [ -f "$LFC_CACHE" ]; then
        echo "Extracting Palomar LFC data..."
        mkdir -p "$LFC_DIR"
        tar -xjf "$LFC_CACHE" -C "$LFC_DIR" 2>&1
        echo "Palomar LFC data extracted to $LFC_DIR"
        rm -f "$LFC_CACHE"
    fi
else
    echo "Palomar LFC data already extracted"
fi

# ============================================================
# Download real HST Eagle Nebula 3-filter FITS from ESA Hubble
# (WFPC2 narrowband: [OIII] 502nm, H-alpha 656nm, [SII] 673nm)
# Used by: stack_dithered_exposures task
# ============================================================
echo "Downloading real HST Eagle Nebula narrowband FITS..."
EAGLE_DIR="/opt/fits_samples/eagle_nebula"
mkdir -p "$EAGLE_DIR"

EAGLE_BASE="https://esahubble.org/static/projects/fits_liberator/datasets/eagle"
for filter_file in 502nmos 656nmos 673nmos; do
    if [ ! -f "$EAGLE_DIR/${filter_file}.fits" ]; then
        echo "Downloading ${filter_file}.zip..."
        wget -q --timeout=60 "${EAGLE_BASE}/${filter_file}.zip" \
            -O "$EAGLE_DIR/${filter_file}.zip" 2>&1 || {
            echo "WARNING: Could not download ${filter_file}.zip"
            continue
        }
        if [ -f "$EAGLE_DIR/${filter_file}.zip" ]; then
            cd "$EAGLE_DIR" && unzip -o "${filter_file}.zip" 2>&1
            rm -f "${filter_file}.zip"
        fi
    else
        echo "${filter_file}.fits already exists"
    fi
done

# ============================================================
# Download real HST NGC 6652 WFPC2 FITS from ESA Hubble
# (Globular cluster - V-band for double star measurement)
# Used by: measure_double_star task
# ============================================================
echo "Downloading real HST NGC 6652 FITS..."
NGC6652_DIR="/opt/fits_samples/ngc6652"
mkdir -p "$NGC6652_DIR"

NGC6652_BASE="https://esahubble.org/static/projects/fits_liberator/datasets/ngc6652"
for filter_file in 555wmos 814wmos; do
    if [ ! -f "$NGC6652_DIR/${filter_file}.fits" ]; then
        echo "Downloading ${filter_file}.zip..."
        wget -q --timeout=60 "${NGC6652_BASE}/${filter_file}.zip" \
            -O "$NGC6652_DIR/${filter_file}.zip" 2>&1 || {
            echo "WARNING: Could not download NGC 6652 ${filter_file}.zip"
            continue
        }
        if [ -f "$NGC6652_DIR/${filter_file}.zip" ]; then
            cd "$NGC6652_DIR" && unzip -o "${filter_file}.zip" 2>&1
            rm -f "${filter_file}.zip"
        fi
    else
        echo "NGC 6652 ${filter_file}.fits already exists"
    fi
done

# ============================================================
# Download real VLT M12 (Messier 12) FITS + star catalog from ESA Hubble
# (V-band and B-band VLT images + 171-star magnitude catalog)
# Used by: photometric_zero_point task
# ============================================================
echo "Downloading real VLT Messier 12 FITS and catalog..."
M12_DIR="/opt/fits_samples/m12"
mkdir -p "$M12_DIR"

M12_BASE="https://esahubble.org/static/projects/fits_liberator/datasets/m12"
for data_file in Vcomb Bcomb; do
    if [ ! -f "$M12_DIR/${data_file}.fits" ]; then
        echo "Downloading ${data_file}.zip..."
        wget -q --timeout=60 "${M12_BASE}/${data_file}.zip" \
            -O "$M12_DIR/${data_file}.zip" 2>&1 || {
            echo "WARNING: Could not download M12 ${data_file}.zip"
            continue
        }
        if [ -f "$M12_DIR/${data_file}.zip" ]; then
            cd "$M12_DIR" && unzip -o "${data_file}.zip" 2>&1
            rm -f "${data_file}.zip"
        fi
    else
        echo "M12 ${data_file}.fits already exists"
    fi
done

# Download the M12 star catalog (Excel with B and V magnitudes for 171 stars)
if [ ! -f "$M12_DIR/m12_B_V.xls" ]; then
    echo "Downloading M12 star magnitude catalog..."
    wget -q --timeout=60 "${M12_BASE}/m12_B_V.xls" \
        -O "$M12_DIR/m12_B_V.xls" 2>&1 || {
        echo "WARNING: Could not download M12 catalog"
    }
fi

# Install xlrd for reading .xls catalog files
pip3 install --no-cache-dir --break-system-packages xlrd 2>/dev/null || \
    pip3 install --no-cache-dir xlrd 2>/dev/null || \
    echo "WARNING: Could not install xlrd"

# Set permissions on all FITS data
chmod -R 755 /opt/fits_samples 2>/dev/null || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== AstroImageJ installation completed ==="
echo "AstroImageJ location: $AIJ_DIR"
echo "FITS samples location: $FITS_DIR"
echo "Real data locations:"
echo "  WASP-12b transit: $WASP12_CACHE"
echo "  Palomar LFC calibration: $LFC_DIR"
echo "  Eagle Nebula 3-filter: $EAGLE_DIR"
echo "  NGC 6652 globular cluster: $NGC6652_DIR"
echo "  M12 globular cluster + catalog: $M12_DIR"
