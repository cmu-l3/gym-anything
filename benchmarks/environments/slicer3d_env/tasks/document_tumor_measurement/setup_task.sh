#!/bin/bash
echo "=== Setting up Document Tumor Measurement Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
OUTPUT_SCREENSHOT="$SCREENSHOT_DIR/tumor_measurement.png"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean any previous task results
rm -f "$OUTPUT_SCREENSHOT" 2>/dev/null || true
rm -f /tmp/tumor_measurement_result.json 2>/dev/null || true
rm -f "$BRATS_DIR"/*.mrk.json 2>/dev/null || true

# Record initial state
ls -la "$SCREENSHOT_DIR"/*.png 2>/dev/null > /tmp/initial_screenshots.txt || echo "none" > /tmp/initial_screenshots.txt

# Prepare BraTS data
echo "Preparing BraTS brain tumor data..."
export BRATS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi
echo "$SAMPLE_ID" > /tmp/task_sample_id.txt

CASE_DIR="$BRATS_DIR/$SAMPLE_ID"
FLAIR_FILE="$CASE_DIR/${SAMPLE_ID}_flair.nii.gz"
SEG_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

# Verify files exist
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR image not found at $FLAIR_FILE"
    ls -la "$CASE_DIR" 2>/dev/null || echo "Case directory not found"
    exit 1
fi
echo "FLAIR image found: $FLAIR_FILE"

if [ ! -f "$SEG_FILE" ]; then
    echo "WARNING: Ground truth segmentation not found at $SEG_FILE"
fi

# Calculate ground truth maximum diameter from segmentation
echo "Computing ground truth maximum tumor diameter..."
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

seg_path = "$SEG_FILE"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"

if not os.path.exists(seg_path):
    print(f"WARNING: Segmentation file not found: {seg_path}")
    # Create minimal ground truth with estimated values
    gt_data = {
        "sample_id": sample_id,
        "max_diameter_mm": 40.0,  # Reasonable estimate
        "max_diameter_slice": 80,
        "tumor_center_ras": [0, 0, 0],
        "estimated": True
    }
    gt_path = os.path.join(gt_dir, f"{sample_id}_diameter_gt.json")
    with open(gt_path, "w") as f:
        json.dump(gt_data, f, indent=2)
    print(f"Created estimated ground truth at {gt_path}")
    sys.exit(0)

print(f"Loading segmentation: {seg_path}")
seg = nib.load(seg_path)
data = seg.get_fdata().astype(np.int32)
affine = seg.affine
voxel_dims = seg.header.get_zooms()[:3]

print(f"Segmentation shape: {data.shape}")
print(f"Voxel dimensions (mm): {voxel_dims}")

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing
# Total tumor = all non-zero labels
tumor_mask = (data > 0)

if not np.any(tumor_mask):
    print("ERROR: No tumor voxels found in segmentation")
    sys.exit(1)

total_tumor_voxels = np.sum(tumor_mask)
print(f"Total tumor voxels: {total_tumor_voxels}")

# Find maximum diameter slice by slice (axial)
max_diameter = 0
max_slice_idx = 0
max_slice_center = [0, 0, 0]

for z in range(data.shape[2]):
    slice_mask = tumor_mask[:, :, z]
    if not np.any(slice_mask):
        continue
    
    # Find bounding box of tumor in this slice
    rows = np.any(slice_mask, axis=1)
    cols = np.any(slice_mask, axis=0)
    
    if not np.any(rows) or not np.any(cols):
        continue
    
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    
    # Calculate diameters in mm
    height_mm = (rmax - rmin + 1) * voxel_dims[0]
    width_mm = (cmax - cmin + 1) * voxel_dims[1]
    
    # Maximum diameter in this slice (could be diagonal)
    slice_diameter = max(height_mm, width_mm)
    
    # Also calculate area-equivalent diameter
    area_pixels = np.sum(slice_mask)
    area_mm2 = area_pixels * voxel_dims[0] * voxel_dims[1]
    equiv_diameter = 2 * np.sqrt(area_mm2 / np.pi)
    
    # Use the larger of bounding box or equivalent diameter
    effective_diameter = max(slice_diameter, equiv_diameter)
    
    if effective_diameter > max_diameter:
        max_diameter = effective_diameter
        max_slice_idx = z
        # Calculate center in RAS coordinates
        center_i = (rmin + rmax) / 2
        center_j = (cmin + cmax) / 2
        center_ijk = [center_i, center_j, z, 1]
        center_ras = affine.dot(center_ijk)[:3]
        max_slice_center = center_ras.tolist()

print(f"Maximum tumor diameter: {max_diameter:.2f} mm at slice {max_slice_idx}")
print(f"Tumor center (RAS): {max_slice_center}")

# Save ground truth
gt_data = {
    "sample_id": sample_id,
    "max_diameter_mm": float(round(max_diameter, 2)),
    "max_diameter_slice": int(max_slice_idx),
    "tumor_center_ras": [float(x) for x in max_slice_center],
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "total_tumor_voxels": int(total_tumor_voxels),
    "estimated": False
}

gt_path = os.path.join(gt_dir, f"{sample_id}_diameter_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
PYEOF

# Set permissions on ground truth
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Launch 3D Slicer with FLAIR image
echo "Launching 3D Slicer with FLAIR image..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the FLAIR file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$FLAIR_FILE' > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start..."
wait_for_slicer 120

# Maximize and focus Slicer window
sleep 5
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "FLAIR image loaded: $FLAIR_FILE"
echo "Output screenshot location: $OUTPUT_SCREENSHOT"
echo ""
echo "TASK: Navigate to the slice with maximum tumor diameter,"
echo "      measure it with a ruler, add a text annotation,"
echo "      and save a screenshot to:"
echo "      $OUTPUT_SCREENSHOT"