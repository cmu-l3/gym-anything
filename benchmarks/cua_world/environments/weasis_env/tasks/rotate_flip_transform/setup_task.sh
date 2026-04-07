#!/bin/bash
echo "=== Setting up rotate_flip_transform task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

EXPORT_DIR="/home/ga/DICOM/exports"
EXPORT_FILE="$EXPORT_DIR/transformed_view.jpg"

# Ensure clean state
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_FILE" 2>/dev/null || true
chown -R ga:ga "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Python script to find a real DICOM, extract pixel data, and save ground truth transformations
python3 << 'PYEOF'
import os
import sys
import glob
import numpy as np

try:
    import pydicom
except ImportError:
    print("Error: pydicom not found")
    sys.exit(1)

# Find first available DICOM file (preferring real data from samples)
search_paths = [
    '/home/ga/DICOM/samples/**/*.dcm',
    '/home/ga/DICOM/samples/**/*.DCM'
]

files = []
for path in search_paths:
    files.extend(glob.glob(path, recursive=True))

if not files:
    print("Error: No DICOM files found in /home/ga/DICOM/samples/")
    sys.exit(1)

# Sort to be deterministic (CT scans preferred)
files.sort()
dcm_file = files[0]

print(f"Selected DICOM: {dcm_file}")

# Save the selected path so bash can launch it
with open('/tmp/selected_dcm.txt', 'w') as f:
    f.write(dcm_file)

try:
    ds = pydicom.dcmread(dcm_file)
    img = ds.pixel_array.astype(float)
    
    # Save original array for verification
    np.save('/tmp/original_pixels.npy', img)
    
    # Compute the expected transformation: 90 CW rotation, then horizontal flip
    # 90 CW = rot90 with k=-1
    # Horizontal flip = fliplr
    transformed = np.fliplr(np.rot90(img, k=-1))
    np.save('/tmp/expected_transform.npy', transformed)
    
    print("Ground truth transformation matrices generated successfully.")
except Exception as e:
    print(f"Error processing DICOM: {e}")
    sys.exit(1)
PYEOF

if [ ! -f /tmp/selected_dcm.txt ]; then
    echo "Failed to select or process a DICOM file."
    exit 1
fi

DICOM_FILE=$(cat /tmp/selected_dcm.txt)
chown ga:ga /tmp/original_pixels.npy /tmp/expected_transform.npy

# Kill any existing Weasis
pkill -f weasis 2>/dev/null || true
sleep 2

# Launch Weasis with the selected DICOM file
echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Maximize Weasis for optimal agent view
WID=$(get_weasis_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_weasis
fi

# Wait a bit more for UI to settle and DICOM to fully render
sleep 3
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="