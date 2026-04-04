#!/bin/bash
echo "=== Setting up Tumor Diameter Measurement Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Prepare BraTS data (downloads from Kaggle if needed)
echo "Preparing BraTS brain tumor data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID that was prepared
SAMPLE_ID=$(cat /tmp/brats_sample_id 2>/dev/null || echo "BraTS2021_00000")
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"

echo "Sample ID: $SAMPLE_ID"
echo "FLAIR file: $FLAIR_FILE"

# Verify data exists
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    echo "Listing available files:"
    ls -la "$BRATS_DIR/" 2>/dev/null || echo "BraTS directory not found"
    exit 1
fi

echo "BraTS data ready!"

# Record initial state
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR" 2>/dev/null || true

# Record existing screenshots
ls -la "$SCREENSHOT_DIR"/*.png 2>/dev/null > /tmp/initial_screenshots.txt || echo "none" > /tmp/initial_screenshots.txt

# Clear previous task results
rm -f /tmp/tumor_measurement_result.json 2>/dev/null || true
rm -f "$SCREENSHOT_DIR/tumor_measurement.png" 2>/dev/null || true

# Compute ground truth maximum diameter from segmentation
echo "Computing ground truth maximum diameter..."
python3 << PYEOF
import numpy as np
import json
import os
import sys

sample_id = "$SAMPLE_ID"
gt_dir = "/var/lib/slicer/ground_truth"
gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")

if not os.path.exists(gt_seg_path):
    print(f"Warning: Ground truth segmentation not found at {gt_seg_path}")
    # Create placeholder ground truth
    gt_info = {
        "sample_id": sample_id,
        "max_diameter_mm": 50.0,
        "max_diameter_slice": 75,
        "tolerance_percent": 20,
        "min_acceptable_mm": 40.0,
        "max_acceptable_mm": 60.0,
        "gt_available": False
    }
    gt_path = "/tmp/tumor_diameter_gt.json"
    with open(gt_path, 'w') as f:
        json.dump(gt_info, f, indent=2)
    print(f"Created placeholder ground truth")
    sys.exit(0)

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

print(f"Loading ground truth: {gt_seg_path}")
seg = nib.load(gt_seg_path)
data = seg.get_fdata().astype(np.int32)
spacing = seg.header.get_zooms()[:3]

print(f"Segmentation shape: {data.shape}")
print(f"Voxel spacing: {spacing} mm")

# Tumor is any non-zero label (BraTS: 1=necrotic, 2=edema, 4=enhancing)
tumor_mask = (data > 0)
total_tumor_voxels = np.sum(tumor_mask)
print(f"Total tumor voxels: {total_tumor_voxels}")

if total_tumor_voxels == 0:
    print("Warning: No tumor found in segmentation!")
    gt_info = {
        "sample_id": sample_id,
        "max_diameter_mm": 50.0,
        "max_diameter_slice": 75,
        "tolerance_percent": 20,
        "min_acceptable_mm": 40.0,
        "max_acceptable_mm": 60.0,
        "gt_available": False
    }
else:
    max_diameter = 0
    max_slice_idx = 0
    
    for z in range(data.shape[2]):
        slice_mask = tumor_mask[:, :, z]
        if not np.any(slice_mask):
            continue
        
        # Method 1: Bounding box diameter (clinical approach)
        rows = np.any(slice_mask, axis=1)
        cols = np.any(slice_mask, axis=0)
        if not np.any(rows) or not np.any(cols):
            continue
            
        rmin, rmax = np.where(rows)[0][[0, -1]]
        cmin, cmax = np.where(cols)[0][[0, -1]]
        
        width_mm = (cmax - cmin + 1) * spacing[0]
        height_mm = (rmax - rmin + 1) * spacing[1]
        bbox_diameter = max(width_mm, height_mm)
        
        if bbox_diameter > max_diameter:
            max_diameter = bbox_diameter
            max_slice_idx = z

    print(f"Maximum diameter: {max_diameter:.1f} mm at slice {max_slice_idx}")
    
    tolerance_pct = 20
    gt_info = {
        "sample_id": sample_id,
        "max_diameter_mm": float(round(max_diameter, 2)),
        "max_diameter_slice": int(max_slice_idx),
        "tolerance_percent": tolerance_pct,
        "min_acceptable_mm": float(round(max_diameter * (1 - tolerance_pct/100), 2)),
        "max_acceptable_mm": float(round(max_diameter * (1 + tolerance_pct/100), 2)),
        "gt_available": True,
        "total_tumor_voxels": int(total_tumor_voxels),
        "voxel_spacing_mm": [float(s) for s in spacing]
    }

gt_path = "/tmp/tumor_diameter_gt.json"
with open(gt_path, 'w') as f:
    json.dump(gt_info, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"Acceptable measurement range: {gt_info['min_acceptable_mm']:.1f} - {gt_info['max_acceptable_mm']:.1f} mm")
PYEOF

# Ensure permissions
chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true
chmod 666 /tmp/tumor_diameter_gt.json 2>/dev/null || true

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the FLAIR volume
echo "Launching 3D Slicer with FLAIR volume..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$FLAIR_FILE" > /tmp/slicer_launch.log 2>&1 &
SLICER_PID=$!
echo "Slicer PID: $SLICER_PID"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..90}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer" | head -1)
        if [ -n "$WINDOW" ]; then
            echo "3D Slicer window detected at iteration $i"
            break
        fi
    fi
    sleep 2
done

# Wait additional time for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "Warning: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo "FLAIR volume loaded: $FLAIR_FILE"
echo ""
echo "TASK INSTRUCTIONS:"
echo "1. Navigate through axial slices to find the largest tumor cross-section"
echo "2. Use Markups > Line tool to measure the maximum diameter"
echo "3. Save screenshot to: ~/Documents/SlicerData/Screenshots/tumor_measurement.png"
echo ""