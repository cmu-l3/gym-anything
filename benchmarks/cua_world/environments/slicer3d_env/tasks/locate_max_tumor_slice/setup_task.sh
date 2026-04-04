#!/bin/bash
echo "=== Setting up Locate Maximum Tumor Cross-Section Slice Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean previous task artifacts
rm -f /tmp/max_slice_task_result.json 2>/dev/null || true
rm -f /tmp/fiducial_positions.json 2>/dev/null || true

# Prepare BraTS data
echo "Preparing BraTS brain tumor data..."
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

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
    exit 1
fi
echo "FLAIR file found: $FLAIR_FILE"

# Compute ground truth maximum slice from segmentation
echo "Computing ground truth maximum tumor slice..."
python3 << 'PYEOF'
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

# Get paths from environment or use defaults
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")

seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
flair_path = os.path.join(brats_dir, sample_id, f"{sample_id}_flair.nii.gz")

if not os.path.exists(seg_path):
    print(f"ERROR: Segmentation not found at {seg_path}")
    sys.exit(1)

print(f"Loading segmentation from {seg_path}")
seg_nii = nib.load(seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
spacing = seg_nii.header.get_zooms()[:3]
affine = seg_nii.affine

print(f"Segmentation shape: {seg_data.shape}")
print(f"Voxel spacing: {spacing}")
print(f"Labels present: {np.unique(seg_data)}")

# BraTS labels: 0=background, 1=necrotic core, 2=edema, 4=enhancing tumor
# For total tumor extent, consider all non-zero labels
tumor_mask = (seg_data > 0)

# Find the axial slice with maximum tumor area
max_area = 0
max_slice_idx = 0
slice_areas = []

for z in range(seg_data.shape[2]):
    slice_mask = tumor_mask[:, :, z]
    area_voxels = np.sum(slice_mask)
    area_mm2 = area_voxels * spacing[0] * spacing[1]
    slice_areas.append(area_mm2)
    
    if area_mm2 > max_area:
        max_area = area_mm2
        max_slice_idx = z

print(f"Maximum tumor area: {max_area:.1f} mm² at slice {max_slice_idx}")

# Calculate tumor centroid on the maximum slice
max_slice = tumor_mask[:, :, max_slice_idx]
if np.any(max_slice):
    rows = np.where(np.any(max_slice, axis=1))[0]
    cols = np.where(np.any(max_slice, axis=0))[0]
    
    if len(rows) > 0 and len(cols) > 0:
        # Get pixel coordinates of centroid
        centroid_row = (rows.min() + rows.max()) / 2.0
        centroid_col = (cols.min() + cols.max()) / 2.0
        
        # Convert to RAS coordinates using affine
        ijk = np.array([centroid_row, centroid_col, max_slice_idx, 1])
        ras = affine @ ijk
        centroid_ras = ras[:3].tolist()
        
        # Also store in mm (image coordinates)
        centroid_mm = [
            float(centroid_row * spacing[0]),
            float(centroid_col * spacing[1]),
            float(max_slice_idx * spacing[2])
        ]
    else:
        centroid_ras = [0, 0, 0]
        centroid_mm = [0, 0, 0]
else:
    centroid_ras = [0, 0, 0]
    centroid_mm = [0, 0, 0]

# Get the Z coordinate in RAS space for the maximum slice
z_ras = (affine @ np.array([0, 0, max_slice_idx, 1]))[2]

# Find slices with >90% of max area (for tolerance calculation)
threshold_90 = max_area * 0.9
near_max_slices = [i for i, a in enumerate(slice_areas) if a >= threshold_90]

# Get total tumor volume
total_tumor_voxels = np.sum(tumor_mask)
total_tumor_volume_mm3 = total_tumor_voxels * np.prod(spacing)

ground_truth = {
    "sample_id": sample_id,
    "max_slice_index": int(max_slice_idx),
    "max_slice_z_ras": float(z_ras),
    "max_area_mm2": float(max_area),
    "centroid_ras": [float(x) for x in centroid_ras],
    "centroid_mm": centroid_mm,
    "volume_shape": list(seg_data.shape),
    "spacing_mm": [float(s) for s in spacing],
    "near_max_slices": near_max_slices,
    "total_tumor_volume_mm3": float(total_tumor_volume_mm3),
    "tolerance_slices": 3
}

gt_output_path = os.path.join(gt_dir, f"{sample_id}_max_slice_gt.json")
with open(gt_output_path, "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"\nGround truth saved to {gt_output_path}")
print(f"Max slice index: {max_slice_idx}")
print(f"Max slice Z (RAS): {z_ras:.2f} mm")
print(f"Tumor centroid (RAS): {centroid_ras}")
print(f"Near-max slices (>90% area): {near_max_slices}")

# Also save to /tmp for easy access
with open("/tmp/max_slice_ground_truth.json", "w") as f:
    json.dump(ground_truth, f, indent=2)

print("Ground truth computation complete")
PYEOF

export SAMPLE_ID GROUND_TRUTH_DIR BRATS_DIR

# Verify ground truth was created
if [ ! -f /tmp/max_slice_ground_truth.json ]; then
    echo "ERROR: Failed to compute ground truth"
    exit 1
fi

echo "Ground truth computed:"
cat /tmp/max_slice_ground_truth.json

# Record initial state - no fiducials should exist yet
echo "0" > /tmp/initial_fiducial_count.txt

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with FLAIR image
echo "Launching 3D Slicer with FLAIR MRI..."

# Create a Python script to set up the view properly
cat > /tmp/setup_slicer_view.py << 'SETUPPY'
import slicer
import time

# Wait for scene to be ready
time.sleep(2)

# Set up the layout to show axial slices prominently
layoutManager = slicer.app.layoutManager()

# Use conventional layout (shows all three slice views + 3D)
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)

# Get the red (axial) slice widget and make it larger/focused
redWidget = layoutManager.sliceWidget("Red")
if redWidget:
    redController = redWidget.sliceController()
    # Fit slice to window
    redController.fitSliceToBackground()

# Get the loaded volume
volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volumeNodes:
    volumeNode = volumeNodes[0]
    print(f"Volume loaded: {volumeNode.GetName()}")
    
    # Center on the volume
    for color in ["Red", "Yellow", "Green"]:
        sliceWidget = layoutManager.sliceWidget(color)
        if sliceWidget:
            sliceLogic = sliceWidget.sliceLogic()
            sliceLogic.FitSliceToAll()
    
    # Set window/level for brain MRI (FLAIR)
    displayNode = volumeNode.GetDisplayNode()
    if displayNode:
        # Auto window/level
        displayNode.AutoWindowLevelOn()

print("View setup complete")
SETUPPY

# Launch Slicer with the FLAIR file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$FLAIR_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Give extra time for volume to load
sleep 5

# Run the setup script to configure the view
echo "Configuring slice views..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/setup_slicer_view.py --no-main-window" > /tmp/slicer_setup.log 2>&1 &
sleep 5

# Focus and maximize Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "BraTS Sample: $SAMPLE_ID"
echo "FLAIR file loaded: $FLAIR_FILE"
echo ""
echo "TASK: Navigate through the axial slices to find the slice showing"
echo "      the MAXIMUM tumor cross-sectional area, then place a fiducial"
echo "      marker at the tumor center on that slice."
echo ""
echo "TIP: Use the slice slider or scroll wheel in the axial (red) view"
echo "     to navigate through slices. The tumor appears as bright regions."
echo ""