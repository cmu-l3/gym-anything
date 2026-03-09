#!/bin/bash
# Setup script for Identify Variable Star task
# Uses REAL WASP-12b calibrated data from University of Louisville
# NO synthetic data generation

echo "=== Setting up Variable Star Identification Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AstroImages/variable_search"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# ============================================================
# Extract real WASP-12b data from cached tarball
# This data was downloaded during environment installation
# ============================================================

WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$WASP12_CACHE" ]; then
    echo "ERROR: WASP-12b data not found at $WASP12_CACHE"
    echo "This data should have been downloaded during environment installation"
    exit 1
fi

echo "Extracting WASP-12b calibrated images..."
tar -xzf "$WASP12_CACHE" -C "$PROJECT_DIR" 2>&1

# ============================================================
# Organize extracted FITS files into working directory
# ============================================================

python3 << 'PYEOF'
import os, glob, json, shutil
from astropy.io import fits
import numpy as np

PROJECT = "/home/ga/AstroImages/variable_search"

# Find all FITS files (they may be in a subdirectory after extraction)
fits_files = sorted(glob.glob(os.path.join(PROJECT, "**/*.fits"), recursive=True) +
                    glob.glob(os.path.join(PROJECT, "**/*.fit"), recursive=True))

print(f"Found {len(fits_files)} FITS files")

# If files are in a subdirectory, move them up to the working directory
for f in fits_files:
    if os.path.dirname(f) != PROJECT:
        dest = os.path.join(PROJECT, os.path.basename(f))
        if not os.path.exists(dest):
            shutil.move(f, dest)

# Clean up empty subdirectories
for d in os.listdir(PROJECT):
    dp = os.path.join(PROJECT, d)
    if os.path.isdir(dp):
        try:
            shutil.rmtree(dp)
        except OSError:
            pass

# Get updated file list
fits_files = sorted(glob.glob(os.path.join(PROJECT, "*.fits")) +
                    glob.glob(os.path.join(PROJECT, "*.fit")))
print(f"Organized {len(fits_files)} FITS files in working directory")

# Read first image to get dimensions and metadata
if fits_files:
    hdr = fits.getheader(fits_files[0])
    shape = fits.getdata(fits_files[0]).shape
    print(f"Image size: {shape}")
    print(f"Filter: {hdr.get('FILTER', 'unknown')}")
    print(f"Object: {hdr.get('OBJECT', 'unknown')}")
    print(f"Exposure: {hdr.get('EXPTIME', 'unknown')} sec")

# Save ground truth info (used by verifier, not visible to agent)
gt = {
    'num_images': len(fits_files),
    'target_star': 'WASP-12',
    'expected_transit_depth_percent': 1.4,
    'data_source': 'University of Louisville',
}
with open('/tmp/variable_star_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)
PYEOF

chown -R ga:ga "$PROJECT_DIR"

# ============================================================
# Record initial state for verification
# ============================================================

echo "0" > /tmp/initial_measurement_count
date +%s > /tmp/task_start_timestamp

# ============================================================
# Create AstroImageJ macro to load image sequence
# ============================================================

MACRO_DIR="/home/ga/.astroimagej/macros"
mkdir -p "$MACRO_DIR"
cat > "$MACRO_DIR/load_sequence.ijm" << 'MACROEOF'
run("Image Sequence...", "open=/home/ga/AstroImages/variable_search/ sort use");
MACROEOF
chown -R ga:ga "$MACRO_DIR"

# ============================================================
# Launch AstroImageJ and load the image sequence
# ============================================================

# Kill any existing instance
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

# Create macro to load image sequence
LOAD_MACRO="/tmp/load_variable_search.ijm"
cat > "$LOAD_MACRO" << 'MACROEOF'
// Load WASP-12 field images as a virtual stack (memory efficient)
run("Image Sequence...", "open=/home/ga/AstroImages/variable_search/ sort use");
wait(5000);
setSlice(1);
MACROEOF
chmod 644 "$LOAD_MACRO"
chown ga:ga "$LOAD_MACRO"

# Launch AstroImageJ with macro
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$AIJ_PATH' -macro '$LOAD_MACRO' > /tmp/astroimagej_ga.log 2>&1" &

echo "AstroImageJ launching with macro..."

# Wait for AstroImageJ to start
echo "Waiting for AstroImageJ to start..."
sleep 10

for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|AstroImageJ\|WASP"; then
        echo "AstroImageJ window detected"
        break
    fi
    sleep 2
done

# Wait for image sequence to load
echo "Waiting for image sequence to load..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "WASP\|fits\|stack\|variable"; then
        echo "Image window detected"
        break
    fi
    sleep 2
done
sleep 5  # Extra time for virtual stack to initialize

# Maximize windows
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "AstroImageJ window maximized"
fi

IMG_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "WASP\|fits\|stack\|variable" | head -1 | awk '{print $1}')
if [ -n "$IMG_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$IMG_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo ""
echo "============================================================"
echo "TASK: Identify Variable Star in WASP-12 Field"
echo "============================================================"
echo ""
echo "Working directory: $PROJECT_DIR"
echo "186 calibrated r-band CCD frames of the WASP-12 stellar field"
echo "are loaded as an image sequence."
echo ""
echo "One of the bright stars in this field shows transit-like"
echo "variability. Use multi-aperture differential photometry to"
echo "identify which star is variable."
echo "============================================================"
