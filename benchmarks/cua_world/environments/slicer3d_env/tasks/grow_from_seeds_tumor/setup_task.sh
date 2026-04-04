#!/bin/bash
echo "=== Setting up Grow From Seeds Tumor Segmentation Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Prepare BraTS data
echo "Preparing BraTS brain tumor data..."
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

export BRATS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_brats_data.sh "BraTS2021_00000"

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi
echo "$SAMPLE_ID" > /tmp/task_sample_id.txt

T1CE_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1ce.nii.gz"
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

echo "Sample ID: $SAMPLE_ID"
echo "T1ce file: $T1CE_FILE"

# Verify data files exist
if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce file not found at $T1CE_FILE"
    ls -la "$BRATS_DIR/$SAMPLE_ID/" 2>/dev/null || echo "Directory not found"
    exit 1
fi

if [ ! -f "$GT_SEG" ]; then
    echo "WARNING: Ground truth segmentation not found at $GT_SEG"
fi

# Clean up any previous task artifacts
rm -f /tmp/grow_seeds_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_segmentation.seg.nrrd" 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_segmentation.nii.gz" 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_segmentation.nrrd" 2>/dev/null || true

# Record initial state - no segmentation should exist
echo "0" > /tmp/initial_segmentation_count.txt
ls -1 "$BRATS_DIR"/*.seg.nrrd "$BRATS_DIR"/*.nii.gz 2>/dev/null | wc -l > /tmp/initial_seg_file_count.txt || echo "0" > /tmp/initial_seg_file_count.txt

# Compute ground truth statistics for verification
echo "Computing ground truth statistics..."
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
gt_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")

if not os.path.exists(gt_path):
    print(f"Ground truth not found at {gt_path}")
    # Create minimal stats
    stats = {
        "sample_id": sample_id,
        "gt_available": False
    }
else:
    print(f"Loading ground truth from {gt_path}")
    gt_nii = nib.load(gt_path)
    gt_data = gt_nii.get_fdata().astype(np.int32)
    voxel_dims = gt_nii.header.get_zooms()[:3]
    voxel_volume_mm3 = float(np.prod(voxel_dims))
    
    # BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing tumor
    # For this task, we focus on enhancing tumor (label 4) as the primary target
    enhancing = (gt_data == 4)
    whole_tumor = (gt_data > 0)
    
    # Get bounding box of tumor for spatial validation
    tumor_coords = np.argwhere(whole_tumor)
    if len(tumor_coords) > 0:
        tumor_center = tumor_coords.mean(axis=0).tolist()
        tumor_bbox_min = tumor_coords.min(axis=0).tolist()
        tumor_bbox_max = tumor_coords.max(axis=0).tolist()
    else:
        tumor_center = [0, 0, 0]
        tumor_bbox_min = [0, 0, 0]
        tumor_bbox_max = [0, 0, 0]
    
    stats = {
        "sample_id": sample_id,
        "gt_available": True,
        "shape": list(gt_data.shape),
        "voxel_dims_mm": [float(v) for v in voxel_dims],
        "voxel_volume_mm3": voxel_volume_mm3,
        "enhancing_voxels": int(np.sum(enhancing)),
        "enhancing_volume_ml": float(np.sum(enhancing) * voxel_volume_mm3 / 1000),
        "whole_tumor_voxels": int(np.sum(whole_tumor)),
        "whole_tumor_volume_ml": float(np.sum(whole_tumor) * voxel_volume_mm3 / 1000),
        "tumor_center_ijk": tumor_center,
        "tumor_bbox_min": tumor_bbox_min,
        "tumor_bbox_max": tumor_bbox_max,
        "affine": gt_nii.affine.tolist()
    }
    
    print(f"Enhancing tumor volume: {stats['enhancing_volume_ml']:.2f} ml")
    print(f"Whole tumor volume: {stats['whole_tumor_volume_ml']:.2f} ml")

# Save stats for verification
stats_path = "/tmp/gt_tumor_stats.json"
with open(stats_path, "w") as f:
    json.dump(stats, f, indent=2)
print(f"Ground truth stats saved to {stats_path}")
PYEOF

# Launch 3D Slicer with the T1ce volume
echo ""
echo "Launching 3D Slicer with BraTS T1ce volume..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Start Slicer with the T1ce file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$T1CE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Give extra time for data to load
sleep 5

# Focus and maximize Slicer window
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    focus_window "$SLICER_WID"
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
take_screenshot /tmp/grow_seeds_initial.png ga

# Verify screenshot was captured
if [ -f /tmp/grow_seeds_initial.png ]; then
    SIZE=$(stat -c %s /tmp/grow_seeds_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "The BraTS T1ce brain MRI is loaded in 3D Slicer."
echo "You should see a brain scan with an enhancing tumor (bright region)."
echo ""
echo "TASK: Use the 'Grow from seeds' effect in Segment Editor to segment the tumor."
echo ""
echo "Required steps:"
echo "  1. Go to Segment Editor module"
echo "  2. Create two segments: 'Tumor' and 'Background'"
echo "  3. Select 'Grow from seeds' effect"
echo "  4. Paint seeds in tumor (bright region) and background (normal brain)"
echo "  5. Click Initialize, then Apply"
echo "  6. Save segmentation to: ~/Documents/SlicerData/BraTS/tumor_segmentation.seg.nrrd"
echo ""