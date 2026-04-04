#!/bin/bash
echo "=== Setting up Create Hemispheric Mirror Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Set up directories
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
OUTPUT_FILE="$EXPORT_DIR/MRHead_mirrored.nrrd"

mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Clear any previous output to ensure fresh task
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/mirror_task_result.json 2>/dev/null || true

# Record initial state
echo "false" > /tmp/initial_output_exists.txt
if [ -f "$OUTPUT_FILE" ]; then
    echo "true" > /tmp/initial_output_exists.txt
    stat -c %Y "$OUTPUT_FILE" > /tmp/initial_output_mtime.txt
fi

# Ensure sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Downloading MRHead sample data..."
    
    # Try primary URL
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Verify download
    if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Primary download failed, trying alternative..."
        wget --timeout=120 -O "$SAMPLE_FILE" \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0)
    echo "Sample file: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"
else
    echo "ERROR: Sample file not found and could not be downloaded"
    exit 1
fi

# Extract original volume properties for verification
echo "Extracting original volume properties..."
python3 << 'PYEOF'
import json
import os

try:
    import nibabel as nib
    import numpy as np
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "numpy"])
    import nibabel as nib
    import numpy as np

sample_file = "/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"

try:
    # Load NRRD file
    import nrrd
except ImportError:
    # Try nibabel for NRRD
    pass

try:
    # Use nibabel which can handle NRRD
    img = nib.load(sample_file)
    data = img.get_fdata()
    affine = img.affine
    
    # Extract direction cosines (3x3 matrix)
    direction = affine[:3, :3]
    
    # Sample some voxel values for verification
    shape = data.shape
    sample_points = [
        (10, shape[1]//2, shape[2]//2),
        (shape[0]//4, shape[1]//2, shape[2]//2),
        (shape[0]//2, shape[1]//2, shape[2]//2),
    ]
    
    sample_values = {}
    for i, (x, y, z) in enumerate(sample_points):
        if x < shape[0] and y < shape[1] and z < shape[2]:
            sample_values[f"point_{i}"] = {
                "coords": [int(x), int(y), int(z)],
                "value": float(data[x, y, z])
            }
    
    original_props = {
        "shape": list(data.shape),
        "direction_matrix": direction.tolist(),
        "affine": affine.tolist(),
        "sample_values": sample_values,
        "data_min": float(np.min(data)),
        "data_max": float(np.max(data)),
        "data_mean": float(np.mean(data))
    }
    
    with open("/tmp/original_volume_props.json", "w") as f:
        json.dump(original_props, f, indent=2)
    
    print(f"Original volume shape: {data.shape}")
    print(f"Direction matrix diagonal: [{direction[0,0]:.3f}, {direction[1,1]:.3f}, {direction[2,2]:.3f}]")
    
except Exception as e:
    print(f"Warning: Could not extract volume properties: {e}")
    # Create minimal props file
    with open("/tmp/original_volume_props.json", "w") as f:
        json.dump({"error": str(e)}, f)
PYEOF

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample file
echo "Launching 3D Slicer with MRHead..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Wait for data to load (check window title for volume name)
echo "Waiting for MRHead to load..."
for i in {1..30}; do
    TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "$TITLE" | grep -qi "MRHead\|Welcome"; then
        echo "Data appears loaded (window: $TITLE)"
        break
    fi
    sleep 2
done

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create a left-right mirrored copy of the MRHead brain MRI"
echo ""
echo "Steps:"
echo "  1. Clone the MRHead volume (Data module > right-click > Clone)"
echo "  2. Create a Linear Transform (Transforms module > Create)"
echo "  3. Set transform to flip L-R (set X scale to -1)"
echo "  4. Apply transform to cloned volume"
echo "  5. Harden the transform"
echo "  6. Save mirrored volume to: $OUTPUT_FILE"
echo ""
echo "Sample file: $SAMPLE_FILE"
echo "Output path: $OUTPUT_FILE"