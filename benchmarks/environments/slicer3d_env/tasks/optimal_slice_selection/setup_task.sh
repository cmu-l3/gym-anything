#!/bin/bash
echo "=== Setting up Optimal Slice Selection Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"

echo "Using sample: $SAMPLE_ID"

# Verify required files exist
FLAIR_FILE="$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz"
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR volume not found at $FLAIR_FILE"
    exit 1
fi
echo "FLAIR volume found: $FLAIR_FILE"

# Verify ground truth segmentation exists
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
if [ ! -f "$GT_SEG" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth segmentation verified"

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time

# Clean up any previous task artifacts
rm -f "$BRATS_DIR/optimal_slices_view.png" 2>/dev/null || true
rm -f "$BRATS_DIR/tumor_dimensions.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/slice_report.json" 2>/dev/null || true
rm -f /tmp/optimal_slice_result.json 2>/dev/null || true

# Compute ground truth optimal slices from segmentation
echo "Computing ground truth optimal slices..."
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

gt_seg_path = "$GT_SEG"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"

# Load ground truth segmentation
print(f"Loading ground truth: {gt_seg_path}")
seg_nii = nib.load(gt_seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
voxel_dims = seg_nii.header.get_zooms()[:3]

print(f"Segmentation shape: {seg_data.shape}")
print(f"Voxel dimensions: {voxel_dims} mm")

# Create tumor mask (all non-zero labels: 1=necrotic, 2=edema, 4=enhancing)
tumor_mask = (seg_data > 0)

# Compute optimal slice for each plane
def compute_optimal_slice(mask, axis):
    """Find slice with maximum tumor area along given axis."""
    areas = []
    for i in range(mask.shape[axis]):
        if axis == 0:
            slice_data = mask[i, :, :]
        elif axis == 1:
            slice_data = mask[:, i, :]
        else:  # axis == 2
            slice_data = mask[:, :, i]
        areas.append(np.sum(slice_data))
    
    optimal_idx = int(np.argmax(areas))
    max_area = int(max(areas))
    return optimal_idx, max_area, areas

def compute_max_diameter(mask, axis, slice_idx, voxel_dims):
    """Compute maximum diameter on a given slice."""
    if axis == 0:
        slice_data = mask[slice_idx, :, :]
        pixel_spacing = (voxel_dims[1], voxel_dims[2])
    elif axis == 1:
        slice_data = mask[:, slice_idx, :]
        pixel_spacing = (voxel_dims[0], voxel_dims[2])
    else:  # axis == 2
        slice_data = mask[:, :, slice_idx]
        pixel_spacing = (voxel_dims[0], voxel_dims[1])
    
    if not np.any(slice_data):
        return 0.0
    
    # Find bounding box
    rows = np.any(slice_data, axis=1)
    cols = np.any(slice_data, axis=0)
    
    if not np.any(rows) or not np.any(cols):
        return 0.0
    
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    
    # Calculate maximum extent in each direction
    height_mm = (rmax - rmin + 1) * pixel_spacing[0]
    width_mm = (cmax - cmin + 1) * pixel_spacing[1]
    
    # Maximum diameter is the larger of the two extents
    # Or could use diagonal: np.sqrt(height_mm**2 + width_mm**2)
    max_diameter = max(height_mm, width_mm)
    
    return float(max_diameter)

# Compute for each plane
# Note: In 3D Slicer with NIfTI:
# - Axial (Red): varies along axis 2 (superior-inferior)
# - Sagittal (Yellow): varies along axis 0 (left-right)
# - Coronal (Green): varies along axis 1 (anterior-posterior)

results = {}

# Axial plane (Red view) - slice through Z axis (axis 2)
axial_idx, axial_area, _ = compute_optimal_slice(tumor_mask, 2)
axial_diam = compute_max_diameter(tumor_mask, 2, axial_idx, voxel_dims)
results['axial'] = {
    'optimal_slice_index': axial_idx,
    'max_area_voxels': axial_area,
    'max_diameter_mm': round(axial_diam, 2)
}
print(f"Axial optimal: slice {axial_idx}, area {axial_area} voxels, diameter {axial_diam:.1f} mm")

# Sagittal plane (Yellow view) - slice through X axis (axis 0)
sagittal_idx, sagittal_area, _ = compute_optimal_slice(tumor_mask, 0)
sagittal_diam = compute_max_diameter(tumor_mask, 0, sagittal_idx, voxel_dims)
results['sagittal'] = {
    'optimal_slice_index': sagittal_idx,
    'max_area_voxels': sagittal_area,
    'max_diameter_mm': round(sagittal_diam, 2)
}
print(f"Sagittal optimal: slice {sagittal_idx}, area {sagittal_area} voxels, diameter {sagittal_diam:.1f} mm")

# Coronal plane (Green view) - slice through Y axis (axis 1)
coronal_idx, coronal_area, _ = compute_optimal_slice(tumor_mask, 1)
coronal_diam = compute_max_diameter(tumor_mask, 1, coronal_idx, voxel_dims)
results['coronal'] = {
    'optimal_slice_index': coronal_idx,
    'max_area_voxels': coronal_area,
    'max_diameter_mm': round(coronal_diam, 2)
}
print(f"Coronal optimal: slice {coronal_idx}, area {coronal_area} voxels, diameter {coronal_diam:.1f} mm")

# Add metadata
results['metadata'] = {
    'sample_id': sample_id,
    'volume_shape': list(seg_data.shape),
    'voxel_dims_mm': [float(v) for v in voxel_dims],
    'total_tumor_voxels': int(np.sum(tumor_mask))
}

# Save ground truth
gt_optimal_path = os.path.join(gt_dir, f"{sample_id}_optimal_slices.json")
with open(gt_optimal_path, 'w') as f:
    json.dump(results, f, indent=2)

print(f"\nGround truth saved to: {gt_optimal_path}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_optimal_slices.json" ]; then
    echo "ERROR: Failed to compute ground truth optimal slices"
    exit 1
fi
echo "Ground truth optimal slices computed"

# Create Slicer Python script to load FLAIR volume
cat > /tmp/load_flair_volume.py << PYEOF
import slicer
import os

sample_dir = "$SAMPLE_DIR"
sample_id = "$SAMPLE_ID"
flair_path = os.path.join(sample_dir, f"{sample_id}_flair.nii.gz")

print(f"Loading FLAIR volume: {flair_path}")

# Load the FLAIR volume
volume_node = slicer.util.loadVolume(flair_path)

if volume_node:
    volume_node.SetName("FLAIR")
    
    # Set optimal window/level for brain MRI
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetAutoWindowLevel(True)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Get volume center for initial positioning
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    # Set initial slice positions to center
    for color, idx in [("Red", 2), ("Green", 1), ("Yellow", 0)]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        sliceNode.SetSliceOffset(center[idx])
    
    print(f"FLAIR loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Volume center: {center}")
else:
    print("ERROR: Could not load FLAIR volume")

print("\nSetup complete - ready for optimal slice selection task")
print("\nView mapping:")
print("  Red view (axial): scroll to find max tumor area in horizontal slices")
print("  Yellow view (sagittal): scroll to find max tumor area in side view")
print("  Green view (coronal): scroll to find max tumor area in front view")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the FLAIR volume
echo "Launching 3D Slicer with FLAIR volume..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_flair_volume.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus and maximize
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/optimal_slice_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Optimal Tumor Visualization Slice Selection"
echo "=================================================="
echo ""
echo "Find the slice in each plane that shows the MAXIMUM tumor cross-section:"
echo ""
echo "1. AXIAL (Red view): Scroll to find slice with largest tumor area"
echo "2. SAGITTAL (Yellow view): Scroll to find slice with largest tumor area"
echo "3. CORONAL (Green view): Scroll to find slice with largest tumor area"
echo ""
echo "For each optimal slice:"
echo "  - Note the slice index"
echo "  - Measure the maximum tumor diameter using a ruler tool"
echo ""
echo "Save your results to:"
echo "  - Screenshot: ~/Documents/SlicerData/BraTS/optimal_slices_view.png"
echo "  - Measurements: ~/Documents/SlicerData/BraTS/tumor_dimensions.mrk.json"
echo "  - Report: ~/Documents/SlicerData/BraTS/slice_report.json"
echo ""