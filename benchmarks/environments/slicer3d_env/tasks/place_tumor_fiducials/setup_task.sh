#!/bin/bash
echo "=== Setting up Place Tumor Fiducials Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MARKUP="/home/ga/Documents/SlicerData/BraTS/tumor_boundaries.mrk.json"

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Prepare BraTS data
echo "Preparing BraTS brain tumor data..."
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Run data preparation script
export BRATS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID
SAMPLE_ID="BraTS2021_00000"
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
fi
echo "Using BraTS sample: $SAMPLE_ID"
echo "$SAMPLE_ID" > /tmp/brats_sample_id

FLAIR_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_flair.nii.gz"

# Verify FLAIR file exists
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR file not found at $FLAIR_FILE"
    ls -la "$BRATS_DIR/$SAMPLE_ID/" 2>/dev/null || echo "Directory does not exist"
    exit 1
fi
echo "FLAIR file found: $FLAIR_FILE"

# Clean any previous task results
rm -f /tmp/fiducials_task_result.json 2>/dev/null || true
rm -f "$OUTPUT_MARKUP" 2>/dev/null || true
rm -f /tmp/initial_markup_count.txt 2>/dev/null || true

# Record initial state - no markups should exist
echo "0" > /tmp/initial_markup_count.txt

# Compute tumor boundary reference from ground truth for verification
echo "Computing tumor boundary reference..."
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
    print(f"ERROR: Ground truth segmentation not found at {gt_seg_path}")
    sys.exit(1)

print(f"Loading ground truth: {gt_seg_path}")
seg_nii = nib.load(gt_seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
affine = seg_nii.affine
voxel_dims = seg_nii.header.get_zooms()[:3]

print(f"Segmentation shape: {seg_data.shape}")
print(f"Voxel dimensions: {voxel_dims} mm")
print(f"Unique labels: {np.unique(seg_data)}")

# Get tumor mask (all non-zero labels)
tumor_mask = (seg_data > 0)
tumor_voxels = np.sum(tumor_mask)
print(f"Total tumor voxels: {tumor_voxels}")

if tumor_voxels == 0:
    print("ERROR: No tumor found in ground truth")
    sys.exit(1)

# Find tumor boundary coordinates
tumor_coords = np.argwhere(tumor_mask)  # Returns (N, 3) array of [i, j, k] indices

# Convert voxel coordinates to RAS world coordinates
def voxel_to_ras(voxel_coords, affine):
    """Convert voxel IJK to RAS coordinates"""
    # Add homogeneous coordinate
    ones = np.ones((voxel_coords.shape[0], 1))
    voxel_homog = np.hstack([voxel_coords, ones])
    ras = affine @ voxel_homog.T
    return ras[:3].T  # Return Nx3 RAS coordinates

ras_coords = voxel_to_ras(tumor_coords, affine)

# Find extreme points
# RAS: R=X (right), A=Y (anterior), S=Z (superior)
superior_idx = np.argmax(ras_coords[:, 2])  # Highest Z
inferior_idx = np.argmin(ras_coords[:, 2])  # Lowest Z
anterior_idx = np.argmax(ras_coords[:, 1])  # Highest Y (most anterior)
posterior_idx = np.argmin(ras_coords[:, 1])  # Lowest Y (most posterior)

boundary_points = {
    "superior": {
        "ras": ras_coords[superior_idx].tolist(),
        "voxel": tumor_coords[superior_idx].tolist()
    },
    "inferior": {
        "ras": ras_coords[inferior_idx].tolist(),
        "voxel": tumor_coords[inferior_idx].tolist()
    },
    "anterior": {
        "ras": ras_coords[anterior_idx].tolist(),
        "voxel": tumor_coords[anterior_idx].tolist()
    },
    "posterior": {
        "ras": ras_coords[posterior_idx].tolist(),
        "voxel": tumor_coords[posterior_idx].tolist()
    }
}

# Calculate tumor extent
z_extent = ras_coords[superior_idx, 2] - ras_coords[inferior_idx, 2]
y_extent = ras_coords[anterior_idx, 1] - ras_coords[posterior_idx, 1]
x_extent = np.max(ras_coords[:, 0]) - np.min(ras_coords[:, 0])

gt_reference = {
    "sample_id": sample_id,
    "tumor_voxel_count": int(tumor_voxels),
    "boundary_points": boundary_points,
    "tumor_extent_mm": {
        "x_lr": float(x_extent),
        "y_ap": float(y_extent),
        "z_si": float(z_extent)
    },
    "tumor_center_ras": [
        float(np.mean(ras_coords[:, 0])),
        float(np.mean(ras_coords[:, 1])),
        float(np.mean(ras_coords[:, 2]))
    ],
    "voxel_dims_mm": [float(v) for v in voxel_dims]
}

# Save reference for verification
ref_path = os.path.join(gt_dir, f"{sample_id}_boundary_ref.json")
with open(ref_path, "w") as f:
    json.dump(gt_reference, f, indent=2)

print(f"\nTumor boundary reference saved to {ref_path}")
print(f"Superior point (highest Z): {boundary_points['superior']['ras']}")
print(f"Inferior point (lowest Z): {boundary_points['inferior']['ras']}")
print(f"Anterior point (highest Y): {boundary_points['anterior']['ras']}")
print(f"Posterior point (lowest Y): {boundary_points['posterior']['ras']}")
print(f"Tumor Z extent: {z_extent:.1f} mm")
print(f"Tumor Y extent: {y_extent:.1f} mm")
PYEOF

# Launch 3D Slicer with FLAIR data loaded
echo ""
echo "Launching 3D Slicer with BraTS FLAIR data..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with FLAIR file
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$FLAIR_FILE" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start and load data
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Additional wait for data to fully load
sleep 5

# Maximize and focus Slicer window
echo "Focusing Slicer window..."
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    focus_window "$SLICER_WID"
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/fiducials_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo "Sample ID: $SAMPLE_ID"
echo "FLAIR loaded: $FLAIR_FILE"
echo "Expected output: $OUTPUT_MARKUP"
echo ""
echo "TASK: Place 4 fiducial markers at tumor boundaries (Superior, Inferior, Anterior, Posterior)"
echo "      and save to: $OUTPUT_MARKUP"