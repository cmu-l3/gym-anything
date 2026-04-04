#!/bin/bash
set -e
echo "=== Setting up import_tiff_stack_reconstruction task ==="

source /workspace/scripts/task_utils.sh

# Configuration
DICOM_SOURCE="/home/ga/DICOM/ct_cranium"
TIFF_DIR="/home/ga/Documents/raw_tiff_stack"
OUTPUT_FILE="/home/ga/Documents/calibrated_model.stl"

# 1. Prepare Directory Structure
mkdir -p "$TIFF_DIR"
# Clean up any previous run artifacts
rm -f "$OUTPUT_FILE"
rm -f "$TIFF_DIR"/*

# 2. Generate TIFF Stack from DICOMs
# We use dcmtk (dcmj2pnm) if available, otherwise fallback to Python/ImageMagick
echo "Generating TIFF stack from DICOM source..."

if command -v dcmj2pnm >/dev/null 2>&1; then
    echo "Using dcmj2pnm for conversion..."
    counter=0
    # Process files in alphabetical order to ensure correct stack sequence
    for dcm_file in $(find "$DICOM_SOURCE" -type f | sort); do
        # Check if it's a valid DICOM header before trying to convert
        if dcmdump "$dcm_file" >/dev/null 2>&1; then
            outfile=$(printf "$TIFF_DIR/image_%03d.tif" "$counter")
            # +Ot: write TIFF, +Wm: write raw pixel data (monochrome)
            dcmj2pnm +Ot "$dcm_file" "$outfile" 2>/dev/null || true
            counter=$((counter + 1))
        fi
    done
else
    echo "dcmtk not found, falling back to Python conversion..."
    # Fallback script using numpy/PIL if available, or just mocking data if strictly necessary
    # (Assuming basic python env is available as per env definition)
    python3 -c "
import os, glob, sys
try:
    import pydicom
    from PIL import Image
    import numpy as np
except ImportError:
    print('Missing python dependencies for conversion')
    sys.exit(1)

files = sorted(glob.glob('$DICOM_SOURCE/*'))
out_dir = '$TIFF_DIR'
for i, f in enumerate(files):
    try:
        ds = pydicom.dcmread(f)
        arr = ds.pixel_array
        # Normalize to 8-bit for simple TIFF export if needed, or keep 16-bit
        # Standard TIFFs from scanners are often 16-bit.
        img = Image.fromarray(arr)
        img.save(os.path.join(out_dir, f'image_{i:03d}.tif'))
    except Exception as e:
        pass
"
fi

file_count=$(ls -1 "$TIFF_DIR"/*.tif 2>/dev/null | wc -l)
echo "Generated $file_count TIFF files in $TIFF_DIR"

if [ "$file_count" -lt 10 ]; then
    echo "ERROR: Failed to generate sufficient TIFF files."
    exit 1
fi

# Set permissions
chown -R ga:ga "$TIFF_DIR"
chown ga:ga "/home/ga/Documents"

# 3. Reset Application State
pkill -f invesalius 2>/dev/null || true
pkill -f "br.gov.cti.invesalius" 2>/dev/null || true
sleep 2

# 4. Launch InVesalius (Clean state, no files loaded)
# We do NOT use -i here because the user must manually import
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch > /tmp/invesalius_ga.log 2>&1 &"

if ! wait_for_invesalius 120; then
    echo "InVesalius launch timeout"
    exit 1
fi
sleep 3
dismiss_startup_dialogs
focus_invesalius || true

# Maximize window
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

# 5. Record Initial State
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="