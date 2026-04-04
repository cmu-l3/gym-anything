#!/bin/bash
echo "=== Setting up Plan Biopsy Trajectory task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create directories
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Clear previous task results
rm -f /tmp/trajectory_task_result.json 2>/dev/null || true
rm -f /tmp/markup_data.json 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_target.txt" 2>/dev/null || true

# Ensure BraTS data is prepared
echo "Preparing BraTS brain tumor data..."
bash /workspace/scripts/prepare_brats_data.sh

# Get the sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

echo "Using sample: $SAMPLE_ID"

# Verify T1ce file exists
T1CE_FILE="$BRATS_DIR/$SAMPLE_ID/${SAMPLE_ID}_t1ce.nii.gz"
if [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce file not found at $T1CE_FILE"
    ls -la "$BRATS_DIR/$SAMPLE_ID/" 2>/dev/null || echo "Sample directory does not exist"
    exit 1
fi
echo "T1ce file found: $T1CE_FILE"

# Calculate tumor centroid and create target file for agent
echo "Calculating tumor centroid from ground truth segmentation..."
python3 << PYEOF
import os
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

sample_id = "$SAMPLE_ID"
gt_dir = "$GROUND_TRUTH_DIR"
brats_dir = "$BRATS_DIR"

# Load ground truth segmentation
seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
if not os.path.exists(seg_path):
    print(f"ERROR: Segmentation not found at {seg_path}")
    exit(1)

print(f"Loading segmentation from {seg_path}")
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata()
affine = seg_nii.affine

# Find tumor voxels (any label > 0 in BraTS: 1=necrotic, 2=edema, 4=enhancing)
tumor_mask = seg_data > 0
tumor_coords = np.argwhere(tumor_mask)

if len(tumor_coords) == 0:
    print("ERROR: No tumor voxels found in segmentation")
    exit(1)

print(f"Found {len(tumor_coords)} tumor voxels")

# Calculate centroid in voxel coordinates
centroid_voxel = tumor_coords.mean(axis=0)
print(f"Centroid (voxel): {centroid_voxel}")

# Convert to RAS coordinates using affine transformation
centroid_ras_homogeneous = np.append(centroid_voxel, 1)
centroid_ras = affine.dot(centroid_ras_homogeneous)[:3]
print(f"Centroid (RAS): {centroid_ras}")

# Calculate bounding box for entry point validation
tumor_min = tumor_coords.min(axis=0)
tumor_max = tumor_coords.max(axis=0)

# Convert bounds to RAS
min_ras = affine.dot(np.append(tumor_min, 1))[:3]
max_ras = affine.dot(np.append(tumor_max, 1))[:3]

# Get image bounds
img_shape = seg_data.shape
voxel_spacing = seg_nii.header.get_zooms()[:3]

# Calculate superior boundary (for entry point reference)
# Superior is typically +S direction in RAS
superior_bound_voxel = np.array([img_shape[0]//2, img_shape[1]//2, img_shape[2]-1])
superior_bound_ras = affine.dot(np.append(superior_bound_voxel, 1))[:3]

# Save comprehensive ground truth for verification (hidden from agent)
gt_data = {
    "sample_id": sample_id,
    "centroid_voxel": centroid_voxel.tolist(),
    "centroid_ras": centroid_ras.tolist(),
    "tumor_bounds_min_voxel": tumor_min.tolist(),
    "tumor_bounds_max_voxel": tumor_max.tolist(),
    "tumor_bounds_min_ras": min_ras.tolist(),
    "tumor_bounds_max_ras": max_ras.tolist(),
    "image_shape": list(seg_data.shape),
    "voxel_spacing": [float(v) for v in voxel_spacing],
    "affine": affine.tolist(),
    "superior_bound_ras": superior_bound_ras.tolist(),
    "tumor_voxel_count": int(np.sum(tumor_mask)),
}

gt_path = os.path.join(gt_dir, f"{sample_id}_trajectory_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved to {gt_path}")

# Create simplified target file for agent (just the coordinates they need)
target_file = os.path.join(brats_dir, "tumor_target.txt")
with open(target_file, 'w') as f:
    f.write("=" * 50 + "\\n")
    f.write("TUMOR TARGET COORDINATES FOR BIOPSY PLANNING\\n")
    f.write("=" * 50 + "\\n\\n")
    f.write("Target Location (tumor center) in RAS coordinates:\\n")
    f.write("-" * 50 + "\\n")
    f.write(f"  R (Right-Left):           {centroid_ras[0]:>8.1f} mm\\n")
    f.write(f"  A (Anterior-Posterior):   {centroid_ras[1]:>8.1f} mm\\n")
    f.write(f"  S (Superior-Inferior):    {centroid_ras[2]:>8.1f} mm\\n")
    f.write("-" * 50 + "\\n\\n")
    f.write("INSTRUCTIONS:\\n")
    f.write("1. Create a Line markup in 3D Slicer\\n")
    f.write("2. Place FIRST point at entry (scalp surface, superior to target)\\n")
    f.write("3. Place SECOND point at target (coordinates above)\\n")
    f.write("4. Rename markup to: Biopsy_Trajectory\\n\\n")
    f.write("Note: Entry point S coordinate should be HIGHER than target S coordinate\\n")
    f.write("      (needle enters from above the tumor)\\n")

os.chmod(target_file, 0o644)
print(f"Target coordinates file created at {target_file}")
print(f"\\nTarget RAS: R={centroid_ras[0]:.1f}, A={centroid_ras[1]:.1f}, S={centroid_ras[2]:.1f}")
PYEOF

# Check if Python script succeeded
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to calculate tumor centroid"
    exit 1
fi

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true

# Kill any existing Slicer instance
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with T1ce volume
echo "Launching 3D Slicer with brain MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$T1CE_FILE" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 120

# Additional wait for data to load
sleep 5

# Maximize and focus window
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    echo "Slicer window found: $SLICER_WID"
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
else
    echo "Warning: Could not find Slicer window ID"
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png ga

echo ""
echo "=== Task setup complete ==="
echo "Brain MRI loaded: $T1CE_FILE"
echo "Target coordinates file: $BRATS_DIR/tumor_target.txt"
echo ""
echo "TASK: Create a Line markup named 'Biopsy_Trajectory'"
echo "      First point: entry on scalp (superior)"
echo "      Second point: tumor center (target)"