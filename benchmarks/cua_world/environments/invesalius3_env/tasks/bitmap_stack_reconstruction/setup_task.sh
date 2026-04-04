#!/bin/bash
set -e

echo "=== Setting up bitmap_stack_reconstruction task ==="

source /workspace/scripts/task_utils.sh

# Directory definitions
DICOM_SOURCE="/opt/invesalius/sample_data/ct_cranium"
BMP_OUTPUT_DIR="/home/ga/Documents/scan_images"
TASK_FILE="/home/ga/Documents/calibrated_skull.stl"

# Cleanup previous run
rm -rf "$BMP_OUTPUT_DIR"
rm -f "$TASK_FILE"
mkdir -p "$BMP_OUTPUT_DIR"
chown ga:ga "$BMP_OUTPUT_DIR"

# Ensure DICOM source exists (using environment's shared assets)
if [ ! -d "$DICOM_SOURCE" ]; then
    echo "Error: DICOM source not found at $DICOM_SOURCE"
    exit 1
fi

echo "Converting DICOM stack to BMP images..."

# Python script to convert DICOM to BMP using InVesalius's environment libraries
# We assume pydicom and PIL/numpy are available as InVesalius deps.
cat << 'PYEOF' > /tmp/convert_dicom.py
import os
import glob
import sys
import numpy as np

try:
    import pydicom
    from PIL import Image
except ImportError as e:
    print(f"Missing libraries: {e}")
    sys.exit(1)

dicom_dir = sys.argv[1]
output_dir = sys.argv[2]

files = sorted(glob.glob(os.path.join(dicom_dir, "*")))
# Filter for likely DICOM files (skip hidden or text)
dicom_files = [f for f in files if os.path.isfile(f) and not os.path.basename(f).startswith('.')]

print(f"Found {len(dicom_files)} potential DICOM files.")

count = 0
for fpath in dicom_files:
    try:
        ds = pydicom.dcmread(fpath, force=True)
        # Check if it has pixel data
        if not hasattr(ds, 'PixelData'):
            continue
        
        arr = ds.pixel_array
        
        # Normalize to 0-255 for 8-bit BMP
        # CT data is usually 12-bit uint or 16-bit int.
        # We want to preserve bone contrast.
        # Windowing for bone: Level ~400, Width ~1800 (ranges -500 to 1300)
        # Simple normalization: Map min/max to 0-255
        
        arr = arr.astype(float)
        # Apply a rough bone window to make it look like a scan
        # Min -1000 (air), Max 3000 (dense bone)
        # To ensure bone is white and air is black:
        mn = -1024
        mx = 3071
        
        # Rescale intercept/slope if present
        intercept = getattr(ds, 'RescaleIntercept', 0)
        slope = getattr(ds, 'RescaleSlope', 1)
        arr = arr * slope + intercept
        
        # Clip
        arr = np.clip(arr, mn, mx)
        
        # Normalize 0-255
        arr = ((arr - mn) / (mx - mn) * 255.0).astype(np.uint8)
        
        img = Image.fromarray(arr)
        
        # Save as BMP
        # Use sequential numbering for stack import
        out_name = f"image_{count:03d}.bmp"
        img.save(os.path.join(output_dir, out_name))
        count += 1
        
    except Exception as e:
        # Skip non-dicom files
        pass

print(f"Converted {count} images.")
PYEOF

python3 /tmp/convert_dicom.py "$DICOM_SOURCE" "$BMP_OUTPUT_DIR"

# Set permissions for user
chown -R ga:ga "$BMP_OUTPUT_DIR"

# Launch InVesalius (clean slate)
pkill -f invesalius 2>/dev/null || true
sleep 2

# Start InVesalius (without loading data, as agent must import)
echo "Launching InVesalius..."
su - ga -c "DISPLAY=:1 /usr/local/bin/invesalius-launch > /tmp/invesalius_startup.log 2>&1 &"

# Wait for window
if ! wait_for_invesalius 180; then
    echo "InVesalius failed to launch"
    exit 1
fi
sleep 5

# Maximize
WIN_ID=$(get_invesalius_window_id)
if [ -n "$WIN_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WIN_ID" -b add,maximized_vert,maximized_horz || true
fi

dismiss_startup_dialogs || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="