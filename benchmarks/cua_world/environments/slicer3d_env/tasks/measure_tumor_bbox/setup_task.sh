#!/bin/bash
echo "=== Setting up Tumor Bounding Box Measurement Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_FILE="$BRATS_DIR/tumor_bbox_measurements.txt"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Prepare BraTS data
echo "Preparing BraTS brain tumor data..."
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
SAMPLE_ID="BraTS2021_00000"
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
fi
echo "$SAMPLE_ID" > /tmp/bbox_sample_id

CASE_DIR="$BRATS_DIR/$SAMPLE_ID"
FLAIR_FILE="$CASE_DIR/${SAMPLE_ID}_flair.nii.gz"
T1CE_FILE="$CASE_DIR/${SAMPLE_ID}_t1ce.nii.gz"
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

echo "Using sample: $SAMPLE_ID"
echo "FLAIR file: $FLAIR_FILE"

# Verify files exist
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    ls -la "$CASE_DIR" 2>/dev/null || echo "Case directory does not exist"
    exit 1
fi

if [ ! -f "$GT_SEG" ]; then
    echo "ERROR: Ground truth segmentation not found at $GT_SEG"
    exit 1
fi

# Clean any previous results
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/bbox_task_result.json 2>/dev/null || true

# Compute ground truth bounding box from segmentation
echo "Computing ground truth bounding box dimensions..."
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
gt_path = "$GT_SEG"
gt_dir = "$GROUND_TRUTH_DIR"

print(f"Loading ground truth segmentation: {gt_path}")
seg_nii = nib.load(gt_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
affine = seg_nii.affine
header = seg_nii.header

# Get voxel dimensions from header
voxel_dims = header.get_zooms()[:3]
print(f"Voxel dimensions: {voxel_dims} mm")

# BraTS labels: 0=background, 1=necrotic/non-enhancing, 2=edema, 4=enhancing
# For bounding box, we want tumor core (labels 1 and 4)
tumor_mask = (seg_data == 1) | (seg_data == 4)

if not np.any(tumor_mask):
    print("WARNING: No tumor core found, using all tumor labels")
    tumor_mask = (seg_data > 0)

if not np.any(tumor_mask):
    print("ERROR: No tumor found in segmentation")
    sys.exit(1)

tumor_voxels = np.sum(tumor_mask)
print(f"Tumor voxels (core): {tumor_voxels}")

# Find bounding box in voxel coordinates
coords = np.where(tumor_mask)
x_min, x_max = coords[0].min(), coords[0].max()
y_min, y_max = coords[1].min(), coords[1].max()
z_min, z_max = coords[2].min(), coords[2].max()

print(f"Voxel bounds: X[{x_min}-{x_max}], Y[{y_min}-{y_max}], Z[{z_min}-{z_max}]")

# Calculate dimensions in mm
# Add 1 to get actual span (e.g., voxels 10 to 20 = 11 voxels)
width_mm = (x_max - x_min + 1) * voxel_dims[0]  # X = Left-Right
depth_mm = (y_max - y_min + 1) * voxel_dims[1]  # Y = Anterior-Posterior
height_mm = (z_max - z_min + 1) * voxel_dims[2] # Z = Superior-Inferior

# Calculate bounding volume
bounding_volume = width_mm * depth_mm * height_mm

# Calculate centroid
centroid_voxel = [
    (x_min + x_max) / 2,
    (y_min + y_max) / 2,
    (z_min + z_max) / 2
]

# Convert centroid to RAS coordinates
centroid_ras = nib.affines.apply_affine(affine, centroid_voxel)

print(f"\nGround Truth Bounding Box:")
print(f"  Width (L-R):  {width_mm:.2f} mm")
print(f"  Depth (A-P):  {depth_mm:.2f} mm")
print(f"  Height (S-I): {height_mm:.2f} mm")
print(f"  Volume:       {bounding_volume:.2f} mm³")
print(f"  Centroid RAS: {centroid_ras}")

# Save ground truth
gt_bbox = {
    "sample_id": sample_id,
    "width_mm": float(width_mm),
    "depth_mm": float(depth_mm),
    "height_mm": float(height_mm),
    "bounding_volume_mm3": float(bounding_volume),
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "bbox_voxels": {
        "x_min": int(x_min), "x_max": int(x_max),
        "y_min": int(y_min), "y_max": int(y_max),
        "z_min": int(z_min), "z_max": int(z_max)
    },
    "centroid_ras": [float(c) for c in centroid_ras],
    "tumor_voxels": int(tumor_voxels)
}

gt_path_json = os.path.join(gt_dir, f"{sample_id}_bbox_gt.json")
with open(gt_path_json, 'w') as f:
    json.dump(gt_bbox, f, indent=2)

print(f"\nGround truth saved to: {gt_path_json}")

# Also save to temp for export script
with open("/tmp/bbox_ground_truth.json", 'w') as f:
    json.dump(gt_bbox, f, indent=2)
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to compute ground truth"
    exit 1
fi

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod -R 755 "$BRATS_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Launch 3D Slicer with FLAIR volume
echo ""
echo "Launching 3D Slicer with BraTS FLAIR volume..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with FLAIR file
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$FLAIR_FILE' > /tmp/slicer_bbox.log 2>&1 &"

echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for Slicer window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/bbox_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Measure the bounding box dimensions of the brain tumor"
echo ""
echo "The FLAIR MRI is loaded showing a brain with glioma."
echo "You need to:"
echo "1. Segment the tumor using Segment Editor"
echo "2. Use Segment Statistics to get bounding box dimensions"
echo "3. Save measurements to: $OUTPUT_FILE"
echo ""
echo "Output format required:"
echo "  Tumor Bounding Box Dimensions (mm):"
echo "  Width (L-R): XX.X"
echo "  Depth (A-P): XX.X"
echo "  Height (S-I): XX.X"
echo "  Total Bounding Volume: XXXX.X mm³"