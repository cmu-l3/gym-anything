#!/bin/bash
# Create a deliberately flawed segmentation for the Segmentation QC task
# Takes the BraTS ground truth and introduces specific, verifiable errors
#
# Errors introduced:
# 1. Under-segmentation: Remove ~20% of tumor from one region
# 2. Over-segmentation: Add a false positive blob near the tumor
# 3. Boundary roughening: Erode tumor boundary in upper half
#
# This script depends on BraTS data being already prepared (prepare_brats_data.sh)

set -e

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_BROKEN="$BRATS_DIR/ai_segmentation.nii.gz"

echo "=== Creating Broken Segmentation for QC Task ==="

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

# Verify ground truth exists
if [ ! -f "$GT_SEG" ]; then
    echo "ERROR: Ground truth segmentation not found at $GT_SEG"
    echo "BraTS data must be prepared first (run prepare_brats_data.sh)"
    exit 1
fi

echo "Using ground truth: $GT_SEG"
echo "Output: $OUTPUT_BROKEN"

# Check if broken segmentation already exists
if [ -f "$OUTPUT_BROKEN" ] && [ -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_broken_errors.json" ]; then
    echo "Broken segmentation already exists"
    exit 0
fi

# Create the broken segmentation using Python
python3 << 'PYEOF'
import os
import sys
import json

gt_path = os.environ.get("GT_SEG", "/var/lib/slicer/ground_truth/BraTS2021_00000_seg.nii.gz")
output_path = os.environ.get("OUTPUT_BROKEN", "/home/ga/Documents/SlicerData/BraTS/ai_segmentation.nii.gz")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")

# Ensure dependencies
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

from scipy.ndimage import binary_dilation, binary_erosion, label as scipy_label

print(f"Loading ground truth: {gt_path}")
seg = nib.load(gt_path)
data = seg.get_fdata().astype(np.int32)
broken = data.copy()

rng = np.random.RandomState(42)
errors_info = {}

print(f"Ground truth shape: {data.shape}")
print(f"Ground truth labels: {np.unique(data)}")
print(f"Total tumor voxels: {np.sum(data > 0)}")

# BraTS labels: 0=bg, 1=necrotic, 2=edema, 4=enhancing

# ============================================================
# ERROR 1: Under-segmentation
# Remove a chunk of the tumor (simulate AI missing a region)
# ============================================================
tumor_mask = (data > 0)
labeled_arr, n_components = scipy_label(tumor_mask)

if n_components > 0:
    # Find the largest connected component
    component_sizes = [np.sum(labeled_arr == i) for i in range(1, n_components + 1)]
    largest = np.argmax(component_sizes) + 1
    component_coords = np.argwhere(labeled_arr == largest)

    if len(component_coords) > 100:
        # Find the centroid
        centroid = component_coords.mean(axis=0)

        # Find an edge point (farthest from centroid)
        distances = np.linalg.norm(component_coords - centroid, axis=1)
        edge_idx = np.argmax(distances)
        edge_point = component_coords[edge_idx]

        # Remove voxels within a radius of the edge point (simulate under-segmentation)
        removal_radius = 12  # voxels
        voxel_distances = np.linalg.norm(component_coords - edge_point, axis=1)
        remove_mask = voxel_distances < removal_radius

        removed_count = 0
        for coord in component_coords[remove_mask]:
            broken[coord[0], coord[1], coord[2]] = 0
            removed_count += 1

        errors_info['under_segmentation'] = {
            'location': edge_point.tolist(),
            'radius_voxels': removal_radius,
            'voxels_removed': removed_count,
            'description': 'Removed a spherical region near tumor edge'
        }
        print(f"ERROR 1: Removed {removed_count} voxels near edge ({edge_point})")

# ============================================================
# ERROR 2: Over-segmentation (false positive)
# Add a false positive blob near but outside the real tumor
# ============================================================
if n_components > 0 and len(component_coords) > 100:
    # Place false positive offset from centroid
    offset = rng.choice([-20, 20], size=3)
    fp_center = (centroid + offset).astype(int)
    fp_center = np.clip(fp_center, 15, np.array(data.shape) - 15)

    # Create a small ellipsoid as false positive
    fp_count = 0
    for dx in range(-8, 9):
        for dy in range(-8, 9):
            for dz in range(-5, 6):
                if (dx / 8) ** 2 + (dy / 8) ** 2 + (dz / 5) ** 2 <= 1:
                    x = fp_center[0] + dx
                    y = fp_center[1] + dy
                    z = fp_center[2] + dz
                    if (0 <= x < data.shape[0] and
                            0 <= y < data.shape[1] and
                            0 <= z < data.shape[2]):
                        if data[x, y, z] == 0:  # Only in non-tumor area
                            broken[x, y, z] = 1  # Mark as necrotic tumor
                            fp_count += 1

    errors_info['over_segmentation'] = {
        'center': fp_center.tolist(),
        'approximate_radius_voxels': 8,
        'voxels_added': fp_count,
        'description': 'Added false positive ellipsoid blob outside real tumor'
    }
    print(f"ERROR 2: Added {fp_count} false positive voxels at ({fp_center})")

# ============================================================
# ERROR 3: Boundary roughening
# Erode the tumor boundary in the upper half to create jagged edges
# ============================================================
if n_components > 0:
    remaining_tumor = (broken > 0)
    eroded = binary_erosion(remaining_tumor, iterations=1)

    # Apply erosion only to upper half (by z-coordinate)
    mid_z = int(centroid[2])
    partial_eroded = remaining_tumor.copy()
    partial_eroded[:, :, mid_z:] = eroded[:, :, mid_z:]

    # Count affected voxels
    boundary_removed = np.sum(remaining_tumor & ~partial_eroded)
    broken[~partial_eroded & (broken > 0)] = 0

    errors_info['boundary_roughening'] = {
        'affected_region': f'z >= {mid_z}',
        'voxels_removed': int(boundary_removed),
        'description': 'Eroded tumor boundary in upper half of volume'
    }
    print(f"ERROR 3: Roughened boundary, removed {boundary_removed} voxels (z >= {mid_z})")

# ============================================================
# Save broken segmentation
# ============================================================
broken_nii = nib.Nifti1Image(broken.astype(np.int16), seg.affine, seg.header)
nib.save(broken_nii, output_path)
print(f"\nBroken segmentation saved to {output_path}")

# Calculate quality metrics
gt_binary = (data > 0)
broken_binary = (broken > 0)

# Dice coefficient
intersection = np.sum(gt_binary & broken_binary)
dice = 2 * intersection / (np.sum(gt_binary) + np.sum(broken_binary)) if (np.sum(gt_binary) + np.sum(broken_binary)) > 0 else 0

errors_info['quality_metrics'] = {
    'dice_before_correction': float(round(dice, 4)),
    'gt_tumor_voxels': int(np.sum(gt_binary)),
    'broken_tumor_voxels': int(np.sum(broken_binary)),
    'under_segmented_voxels': int(np.sum(gt_binary & ~broken_binary)),
    'over_segmented_voxels': int(np.sum(broken_binary & ~gt_binary)),
}

# Save error info for verification
errors_path = os.path.join(gt_dir, f"{sample_id}_broken_errors.json")
with open(errors_path, "w") as f:
    json.dump(errors_info, f, indent=2)

print(f"Error info saved to {errors_path}")
print(f"Dice (broken vs GT): {dice:.4f}")
print(f"Under-segmented: {errors_info['quality_metrics']['under_segmented_voxels']} voxels")
print(f"Over-segmented: {errors_info['quality_metrics']['over_segmented_voxels']} voxels")
PYEOF

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chmod -R 755 "$BRATS_DIR" 2>/dev/null || true

echo ""
echo "=== Broken Segmentation Created ==="
echo "Output: $OUTPUT_BROKEN"
echo "The agent should find and fix the errors in this segmentation"
