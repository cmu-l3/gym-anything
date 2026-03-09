#!/bin/bash
echo "=== Setting up Tumor Volume ABC/2 Estimation Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS 2021 brain tumor data..."
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

export BRATS_DIR GROUND_TRUTH_DIR
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
    # Try alternative locations
    T1CE_FILE=$(find "$BRATS_DIR" -name "*t1ce*.nii.gz" 2>/dev/null | head -1)
fi

if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1-contrast enhanced MRI not found"
    exit 1
fi
echo "Found T1-CE file: $T1CE_FILE"

# Record initial state
date +%s > /tmp/task_start_time.txt
echo "$SAMPLE_ID" > /tmp/task_sample_id.txt

# Clean previous task outputs
rm -f "$BRATS_DIR/measurement_A.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/measurement_B.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/measurement_C.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/volume_estimate.txt" 2>/dev/null || true
rm -f /tmp/abc2_task_result.json 2>/dev/null || true

# Create ground truth reference from segmentation
echo "Computing ground truth tumor volume from segmentation..."
python3 << PYEOF
import os
import sys
import json
import math

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"

try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

# Load ground truth segmentation
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
if not os.path.exists(seg_path):
    print(f"WARNING: Ground truth segmentation not found at {seg_path}")
    # Create minimal ground truth
    gt_data = {
        "sample_id": sample_id,
        "gt_volume_ml": 25.0,  # Default estimate
        "gt_available": False
    }
else:
    seg = nib.load(seg_path)
    seg_data = seg.get_fdata()
    voxel_dims = seg.header.get_zooms()[:3]
    voxel_volume_mm3 = float(np.prod(voxel_dims))
    
    # BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
    # Total tumor = all non-zero labels
    tumor_mask = seg_data > 0
    tumor_voxels = int(np.sum(tumor_mask))
    tumor_volume_mm3 = tumor_voxels * voxel_volume_mm3
    tumor_volume_ml = tumor_volume_mm3 / 1000.0
    
    # Compute bounding box dimensions for reference
    if np.any(tumor_mask):
        coords = np.argwhere(tumor_mask)
        min_coords = coords.min(axis=0)
        max_coords = coords.max(axis=0)
        
        # Dimensions in mm
        dims_voxels = max_coords - min_coords + 1
        dims_mm = [dims_voxels[i] * voxel_dims[i] for i in range(3)]
        
        # Reference diameters (approximate from bounding box)
        ref_A = float(max(dims_mm[0], dims_mm[1]))  # Largest axial
        ref_B = float(min(dims_mm[0], dims_mm[1]))  # Perpendicular axial
        ref_C = float(dims_mm[2])  # Craniocaudal
        
        # Expected ABC/2 volume
        abc2_volume = (ref_A * ref_B * ref_C) / 2 / 1000.0
    else:
        ref_A, ref_B, ref_C = 30.0, 25.0, 20.0
        abc2_volume = 7.5
    
    gt_data = {
        "sample_id": sample_id,
        "gt_volume_ml": round(tumor_volume_ml, 2),
        "gt_voxels": tumor_voxels,
        "voxel_volume_mm3": round(voxel_volume_mm3, 4),
        "ref_diameter_A_mm": round(ref_A, 1),
        "ref_diameter_B_mm": round(ref_B, 1),
        "ref_diameter_C_mm": round(ref_C, 1),
        "expected_abc2_volume_ml": round(abc2_volume, 2),
        "gt_available": True
    }
    
    print(f"Ground truth tumor volume: {tumor_volume_ml:.2f} mL")
    print(f"Reference diameters: A={ref_A:.1f}mm, B={ref_B:.1f}mm, C={ref_C:.1f}mm")
    print(f"Expected ABC/2 volume: {abc2_volume:.2f} mL")

# Save ground truth
gt_output = os.path.join(gt_dir, f"{sample_id}_abc2_gt.json")
with open(gt_output, 'w') as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved to {gt_output}")

# Also save to /tmp for easy access
with open('/tmp/abc2_ground_truth.json', 'w') as f:
    json.dump(gt_data, f, indent=2)
PYEOF

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Launch 3D Slicer with the T1-CE MRI
echo "Launching 3D Slicer with T1-contrast enhanced MRI..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the data file
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Run as ga user
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$T1CE_FILE' > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for Slicer window
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for data to load
echo "Waiting for MRI data to load..."
sleep 10

# Maximize window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
take_screenshot /tmp/abc2_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "T1-CE MRI: $T1CE_FILE"
echo ""
echo "TASK: Measure tumor diameters using ABC/2 method:"
echo "  1. Find the axial slice with largest tumor cross-section"
echo "  2. Measure longest diameter (A) using Markups > Line"
echo "  3. Measure perpendicular diameter (B) on same slice"
echo "  4. Measure craniocaudal extent (C) in sagittal/coronal view"
echo "  5. Calculate volume = (A × B × C) / 2 / 1000 mL"
echo "  6. Save measurements and report to: $BRATS_DIR/"
echo ""