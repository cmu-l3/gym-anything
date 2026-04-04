#!/bin/bash
echo "=== Setting up Create Closed Curve ROI Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Ensure directories exist
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clear previous task results
rm -f /tmp/closed_curve_result.json 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

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
FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    ls -la "$BRATS_DIR/$SAMPLE_ID/" 2>/dev/null || echo "Directory does not exist"
    exit 1
fi

echo "FLAIR file found: $FLAIR_FILE"

# Compute tumor centroid and bounding box from ground truth for verification
echo "Computing tumor reference location from ground truth..."
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
gt_seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")

if not os.path.exists(gt_seg_path):
    print(f"WARNING: Ground truth segmentation not found at {gt_seg_path}")
    # Create minimal reference data
    ref_data = {
        "sample_id": sample_id,
        "tumor_exists": False,
        "tumor_centroid_ras": [0, 0, 0],
        "tumor_bbox_min_ras": [0, 0, 0],
        "tumor_bbox_max_ras": [0, 0, 0],
        "tumor_volume_mm3": 0
    }
else:
    print(f"Loading ground truth from {gt_seg_path}")
    seg_nii = nib.load(gt_seg_path)
    seg_data = seg_nii.get_fdata().astype(np.int32)
    affine = seg_nii.affine
    voxel_dims = seg_nii.header.get_zooms()[:3]
    voxel_volume = float(np.prod(voxel_dims))

    # BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
    # Combine all tumor labels
    tumor_mask = seg_data > 0
    
    if not np.any(tumor_mask):
        print("WARNING: No tumor voxels found in ground truth")
        ref_data = {
            "sample_id": sample_id,
            "tumor_exists": False,
            "tumor_centroid_ras": [0, 0, 0],
            "tumor_bbox_min_ras": [0, 0, 0],
            "tumor_bbox_max_ras": [0, 0, 0],
            "tumor_volume_mm3": 0
        }
    else:
        # Find tumor voxel coordinates
        tumor_coords = np.argwhere(tumor_mask)
        
        # Compute centroid in voxel space
        centroid_voxel = tumor_coords.mean(axis=0)
        
        # Convert to RAS coordinates
        centroid_ras = nib.affines.apply_affine(affine, centroid_voxel)
        
        # Compute bounding box
        bbox_min_voxel = tumor_coords.min(axis=0)
        bbox_max_voxel = tumor_coords.max(axis=0)
        bbox_min_ras = nib.affines.apply_affine(affine, bbox_min_voxel)
        bbox_max_ras = nib.affines.apply_affine(affine, bbox_max_voxel)
        
        # Compute volume
        tumor_volume = np.sum(tumor_mask) * voxel_volume
        
        # Find best axial slice (highest tumor area)
        best_slice = -1
        max_area = 0
        for z in range(seg_data.shape[2]):
            area = np.sum(tumor_mask[:, :, z])
            if area > max_area:
                max_area = area
                best_slice = z
        
        best_slice_ras_z = nib.affines.apply_affine(affine, [0, 0, best_slice])[2]
        
        ref_data = {
            "sample_id": sample_id,
            "tumor_exists": True,
            "tumor_centroid_ras": [float(x) for x in centroid_ras],
            "tumor_centroid_voxel": [float(x) for x in centroid_voxel],
            "tumor_bbox_min_ras": [float(x) for x in bbox_min_ras],
            "tumor_bbox_max_ras": [float(x) for x in bbox_max_ras],
            "tumor_volume_mm3": float(tumor_volume),
            "tumor_voxel_count": int(np.sum(tumor_mask)),
            "best_axial_slice": int(best_slice),
            "best_axial_slice_z_ras": float(best_slice_ras_z),
            "voxel_dims_mm": [float(v) for v in voxel_dims]
        }
        
        print(f"Tumor centroid (RAS): {ref_data['tumor_centroid_ras']}")
        print(f"Tumor volume: {tumor_volume:.1f} mm³")
        print(f"Best axial slice: {best_slice} (z={best_slice_ras_z:.1f} mm)")

# Save reference data for verification
ref_path = os.path.join(gt_dir, f"{sample_id}_tumor_reference.json")
with open(ref_path, "w") as f:
    json.dump(ref_data, f, indent=2)
print(f"Reference data saved to {ref_path}")

# Also save to /tmp for export script
with open("/tmp/tumor_reference.json", "w") as f:
    json.dump(ref_data, f, indent=2)
PYEOF

# Record initial closed curve count (should be 0)
echo "0" > /tmp/initial_curve_count.txt

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the FLAIR file
echo "Launching 3D Slicer with FLAIR sequence..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$FLAIR_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer\|3D Slicer" | head -1 | awk '{print $1}')
        if [ -n "$SLICER_WID" ]; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
done

# Wait for data to load
echo "Waiting for FLAIR data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create a closed curve annotation around the tumor margin"
echo ""
echo "The FLAIR MRI is loaded showing a brain tumor (bright hyperintense region)."
echo "Use the Markups Closed Curve tool to outline the tumor."
echo ""
echo "Requirements:"
echo "  - Create a MarkupsClosedCurve (not fiducials or open curve)"
echo "  - Place at least 10 control points around the tumor"
echo "  - Name the curve 'GTV_Tumor_Margin'"
echo "  - Ensure the curve follows the tumor boundary"
echo ""
echo "BraTS Sample ID: $SAMPLE_ID"
echo "FLAIR file: $FLAIR_FILE"