#!/bin/bash
# Setup script for WASP-12b Exoplanet Transit Detection task
# Downloads real University of Louisville data and pre-loads in AstroImageJ

source /workspace/scripts/task_utils.sh

echo "=== Setting up WASP-12b Exoplanet Transit Detection task ==="

# ============================================================
# TASK SETUP REQUIREMENTS (from user specification):
# - All calibrated FITS images loaded as an image sequence
# - The first image displayed
# - No apertures set, no analysis done
# ============================================================

DATA_DIR="/home/ga/AstroImages/WASP-12b"
RESULTS_DIR="/home/ga/AstroImages/results"
DATA_URL="https://www.astro.louisville.edu/software/astroimagej/examples/WASP-12b_example_calibrated_images.tar.gz"
CACHED_DATA="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga /home/ga/AstroImages

# Clear previous state
rm -f /tmp/aij_state.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/transit_params.json 2>/dev/null || true

# Record initial state for verification
echo "0" > /tmp/initial_lightcurve_count
ls -1 "$RESULTS_DIR"/*.tbl "$RESULTS_DIR"/*.txt "$RESULTS_DIR"/*.csv 2>/dev/null | wc -l > /tmp/initial_results_count || echo "0" > /tmp/initial_results_count

# ============================================================
# Download WASP-12b calibrated images (4.3GB)
# Use cached version if available, otherwise download
# ============================================================

FITS_COUNT=$(ls -1 "$DATA_DIR"/*.fits 2>/dev/null | wc -l || echo "0")

if [ "$FITS_COUNT" -lt 100 ]; then
    echo "Downloading WASP-12b calibrated images..."

    # Check for cached data first
    if [ -f "$CACHED_DATA" ]; then
        echo "Using cached data from $CACHED_DATA"
        cd /tmp
        tar -xzf "$CACHED_DATA"
        mv WASP-12b/*.fits "$DATA_DIR/" 2>/dev/null || true
        rm -rf WASP-12b
    else
        echo "Downloading from University of Louisville (4.3GB - this may take a while)..."
        cd /tmp
        wget -q --show-progress "$DATA_URL" -O wasp12b_data.tar.gz 2>&1 || {
            echo "ERROR: Failed to download data"
            exit 1
        }

        echo "Extracting FITS files..."
        tar -xzf wasp12b_data.tar.gz
        mv WASP-12b/*.fits "$DATA_DIR/" 2>/dev/null || true
        rm -rf WASP-12b wasp12b_data.tar.gz

        # Cache for future use
        mkdir -p /opt/fits_samples
        cp /tmp/wasp12b_data.tar.gz "$CACHED_DATA" 2>/dev/null || true
    fi

    chown -R ga:ga "$DATA_DIR"
fi

# Verify FITS files
FITS_COUNT=$(ls -1 "$DATA_DIR"/*.fits 2>/dev/null | wc -l || echo "0")
echo "Found $FITS_COUNT FITS files"

if [ "$FITS_COUNT" -lt 100 ]; then
    echo "ERROR: Expected ~200+ FITS files, found only $FITS_COUNT"
    exit 1
elif [ "$FITS_COUNT" -lt 200 ]; then
    echo "WARNING: Expected ~230 FITS files, found $FITS_COUNT (continuing anyway)"
fi

# ============================================================
# Create macro to load image sequence
# ============================================================

LOAD_MACRO="/tmp/load_wasp12b.ijm"
cat > "$LOAD_MACRO" << 'MACROEOF'
// Load WASP-12b images as a virtual stack (memory efficient)
run("Image Sequence...", "open=/home/ga/AstroImages/WASP-12b sort use");
wait(5000);
// Go to first slice
setSlice(1);
MACROEOF
chmod 644 "$LOAD_MACRO"
chown ga:ga "$LOAD_MACRO"

# ============================================================
# Launch AstroImageJ with macro to load images
# ============================================================

echo ""
echo "Launching AstroImageJ with image sequence..."

# Kill any existing AstroImageJ
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

# Find AstroImageJ executable
AIJ_PATH=""
for path in \
    "/usr/local/bin/aij" \
    "/opt/astroimagej/astroimagej/bin/AstroImageJ" \
    "/opt/astroimagej/AstroImageJ/bin/AstroImageJ"; do
    if [ -x "$path" ]; then
        AIJ_PATH="$path"
        break
    fi
done

if [ -z "$AIJ_PATH" ]; then
    echo "ERROR: AstroImageJ not found!"
    exit 1
fi

echo "Found AstroImageJ at: $AIJ_PATH"

# Launch AstroImageJ with macro
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Run as ga user with macro argument
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$AIJ_PATH' -macro '$LOAD_MACRO' > /tmp/astroimagej_ga.log 2>&1" &

echo "AstroImageJ launching with macro..."

# Wait for AstroImageJ to start and load images
echo "Waiting for AstroImageJ to start..."
sleep 10

# Wait for window to appear
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|AstroImageJ\|WASP"; then
        echo "AstroImageJ window detected"
        break
    fi
    sleep 2
done

# Wait for images to load and image window to appear
echo "Waiting for image sequence to load..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "WASP\|fits\|stack"; then
        echo "Image window detected"
        break
    fi
    sleep 2
done
sleep 5  # Give extra time for virtual stack to initialize

# Get the window ID and maximize
sleep 3
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "AstroImageJ window maximized"
fi

# Also maximize any image window
IMG_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "WASP\|fits\|stack" | head -1 | awk '{print $1}')
if [ -n "$IMG_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$IMG_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Verify images loaded
echo "Verifying image sequence loaded..."

# Take screenshot of current state
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Detect Exoplanet Transit in WASP-12 Observations"
echo "============================================================"
echo ""
echo "You have access to AstroImageJ with a sequence of astronomical"
echo "images of the star WASP-12."
echo ""
echo "Your task is to:"
echo "1. Determine if there is evidence of a planetary transit"
echo "2. If yes, measure:"
echo "   - Transit depth (in percent)"
echo "   - Mid-transit time (in BJD_TDB)"
echo "   - Transit duration (in hours)"
echo "3. Calculate planet radius assuming stellar radius = 1.599 R_sun"
echo ""
echo "Target star WASP-12 coordinates:"
echo "  RA:  06:30:32.79"
echo "  Dec: +29:40:20.4"
echo ""
echo "Use differential photometry with comparison stars."
echo ""
echo "Data directory: $DATA_DIR"
echo "Results directory: $RESULTS_DIR"
echo "Number of images: $FITS_COUNT"
echo "============================================================"
