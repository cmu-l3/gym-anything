#!/bin/bash
echo "=== Setting up Measure Tumor-to-Midline Distance Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean previous task results
rm -f /tmp/midline_task_result.json 2>/dev/null || true
rm -f /tmp/midline_ground_truth.json 2>/dev/null || true
rm -f "$SCREENSHOT_DIR/midline_distance.png" 2>/dev/null || true

# Record initial state
ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l > /tmp/initial_screenshot_count.txt || echo "0" > /tmp/initial_screenshot_count.txt

# Prepare BraTS data
echo "Preparing BraTS brain tumor data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

echo "Using BraTS sample: $SAMPLE_ID"

# Verify data exists
T1CE_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1ce.nii.gz"
if [ ! -f "$T1CE_FILE" ]; then
    # Try alternative paths
    T1CE_FILE=$(find "$BRATS_DIR" -name "*t1ce*.nii.gz" -type f | head -1)
    if [ -z "$T1CE_FILE" ]; then
        echo "ERROR: T1CE file not found!"
        exit 1
    fi
fi

echo "T1CE file: $T1CE_FILE"

# Compute ground truth: minimum distance from tumor to midline (x=0)
echo "Computing ground truth midline distance..."
python3 << PYEOF
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"
brats_dir = "$BRATS_DIR"

# Load ground truth segmentation
gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
if not os.path.exists(gt_seg_path):
    print(f"WARNING: Ground truth segmentation not found at {gt_seg_path}")
    # Create minimal ground truth
    gt_data = {
        "sample_id": sample_id,
        "min_distance_to_midline_mm": 25.0,  # Default estimate
        "tumor_center_ras": [30.0, 0.0, 0.0],
        "closest_tumor_point_ras": [15.0, 0.0, 0.0],
        "midline_point_ras": [0.0, 0.0, 0.0],
        "computed": False
    }
else:
    seg_nii = nib.load(gt_seg_path)
    seg_data = seg_nii.get_fdata().astype(np.int32)
    affine = seg_nii.affine
    
    # Get tumor mask (any label > 0)
    tumor_mask = seg_data > 0
    
    if not np.any(tumor_mask):
        print("WARNING: No tumor found in segmentation")
        gt_data = {
            "sample_id": sample_id,
            "min_distance_to_midline_mm": 0.0,
            "tumor_center_ras": [0.0, 0.0, 0.0],
            "closest_tumor_point_ras": [0.0, 0.0, 0.0],
            "midline_point_ras": [0.0, 0.0, 0.0],
            "computed": False
        }
    else:
        # Get voxel coordinates of all tumor voxels
        tumor_voxels = np.argwhere(tumor_mask)
        
        # Convert to RAS coordinates
        # Add homogeneous coordinate
        tumor_voxels_h = np.hstack([tumor_voxels, np.ones((tumor_voxels.shape[0], 1))])
        tumor_ras = (affine @ tumor_voxels_h.T).T[:, :3]
        
        # Midline is at x=0 in RAS coordinates
        # Distance to midline is simply abs(x)
        distances_to_midline = np.abs(tumor_ras[:, 0])
        
        # Find minimum distance
        min_idx = np.argmin(distances_to_midline)
        min_distance = distances_to_midline[min_idx]
        closest_point = tumor_ras[min_idx]
        
        # Compute tumor center
        tumor_center = np.mean(tumor_ras, axis=0)
        
        # The corresponding midline point (same Y, Z as closest tumor point, but X=0)
        midline_point = [0.0, closest_point[1], closest_point[2]]
        
        print(f"Tumor voxels: {len(tumor_voxels)}")
        print(f"Tumor center (RAS): [{tumor_center[0]:.1f}, {tumor_center[1]:.1f}, {tumor_center[2]:.1f}]")
        print(f"Closest tumor point to midline (RAS): [{closest_point[0]:.1f}, {closest_point[1]:.1f}, {closest_point[2]:.1f}]")
        print(f"Minimum distance to midline: {min_distance:.1f} mm")
        
        gt_data = {
            "sample_id": sample_id,
            "min_distance_to_midline_mm": float(min_distance),
            "tumor_center_ras": [float(x) for x in tumor_center],
            "closest_tumor_point_ras": [float(x) for x in closest_point],
            "midline_point_ras": [float(x) for x in midline_point],
            "tumor_voxel_count": int(len(tumor_voxels)),
            "computed": True
        }

# Save ground truth
gt_path = "/tmp/midline_ground_truth.json"
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
PYEOF

# Launch 3D Slicer with the T1CE volume
echo "Launching 3D Slicer with T1CE brain MRI..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the T1CE file
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$T1CE_FILE' > /tmp/slicer_launch.log 2>&1" &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

# Record initial markups count (should be 0)
echo "0" > /tmp/initial_markups_count.txt

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "T1CE file loaded: $T1CE_FILE"
echo ""
echo "TASK: Measure the shortest distance from the tumor edge to the brain midline"
echo "      using the Markups Line (ruler) tool."
echo ""
echo "Save screenshot to: $SCREENSHOT_DIR/midline_distance.png"