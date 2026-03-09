#!/bin/bash
echo "=== Setting up Brain Lesion Localization Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_DIR="$BRATS_DIR/LocalizationReport"

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
FLAIR_FILE="$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz"

echo "Using sample: $SAMPLE_ID"

# Verify FLAIR file exists
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR volume not found at $FLAIR_FILE"
    exit 1
fi
echo "FLAIR volume found: $FLAIR_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" ]; then
    echo "ERROR: Ground truth segmentation not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Compute ground truth centroid from segmentation
echo "Computing ground truth centroid..."
python3 << PYEOF
import nibabel as nib
import numpy as np
import json
import os

gt_seg_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
gt_output_path = "$GROUND_TRUTH_DIR/${SAMPLE_ID}_centroid_gt.json"

# Load ground truth segmentation
seg_nii = nib.load(gt_seg_path)
seg_data = seg_nii.get_fdata().astype(np.int32)
affine = seg_nii.affine

# Get tumor mask (all non-zero labels)
tumor_mask = seg_data > 0

if not np.any(tumor_mask):
    print("ERROR: No tumor found in ground truth!")
    exit(1)

# Compute centroid in voxel coordinates
tumor_coords = np.argwhere(tumor_mask)
centroid_voxel = tumor_coords.mean(axis=0)

# Convert to RAS coordinates using affine
centroid_ras = nib.affines.apply_affine(affine, centroid_voxel)

# Determine laterality based on R coordinate
# In RAS: positive R is patient's right, negative R is patient's left
R_coord = centroid_ras[0]
if R_coord > 5:
    laterality = "right"
elif R_coord < -5:
    laterality = "left"
else:
    laterality = "midline"

midline_distance = abs(R_coord)

# Estimate hemisphere involvement based on coordinates
A_coord = centroid_ras[1]  # Anterior-Posterior
S_coord = centroid_ras[2]  # Superior-Inferior

# Simple hemisphere description
region = "frontal" if A_coord > 0 else "occipital"
hemisphere_desc = f"{laterality} {region}" if laterality != "midline" else f"midline {region}"

# Save ground truth
gt_data = {
    "sample_id": "$SAMPLE_ID",
    "centroid_voxel": centroid_voxel.tolist(),
    "centroid_ras": {
        "R": float(centroid_ras[0]),
        "A": float(centroid_ras[1]),
        "S": float(centroid_ras[2])
    },
    "laterality": laterality,
    "midline_distance_mm": float(midline_distance),
    "hemisphere_involvement": hemisphere_desc,
    "tumor_voxel_count": int(np.sum(tumor_mask)),
    "affine": affine.tolist()
}

with open(gt_output_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth centroid RAS: R={centroid_ras[0]:.1f}, A={centroid_ras[1]:.1f}, S={centroid_ras[2]:.1f}")
print(f"Laterality: {laterality}, Midline distance: {midline_distance:.1f}mm")
print(f"Hemisphere involvement: {hemisphere_desc}")
print(f"Ground truth saved to {gt_output_path}")
PYEOF

# Record initial state
rm -f /tmp/lesion_localization_result.json 2>/dev/null || true
rm -rf "$OUTPUT_DIR" 2>/dev/null || true
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR" 2>/dev/null || true
chmod -R 755 "$OUTPUT_DIR" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time
echo "$(date -Iseconds)" > /tmp/task_start_time_iso

# Create a Slicer Python script to load FLAIR
cat > /tmp/load_flair_volume.py << PYEOF
import slicer
import os

flair_path = "$FLAIR_FILE"
sample_id = "$SAMPLE_ID"

print(f"Loading FLAIR volume for {sample_id}...")

# Load the FLAIR volume
volume_node = slicer.util.loadVolume(flair_path)

if volume_node:
    volume_node.SetName("FLAIR")
    
    # Set appropriate window/level for brain MRI FLAIR
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Auto window/level first, then adjust
        displayNode.SetAutoWindowLevel(True)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views to show the data
    slicer.util.resetSliceViews()
    
    # Center on the data (middle of volume)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Yellow - Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    print(f"FLAIR loaded: {volume_node.GetName()}")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Center position (RAS): {center}")
else:
    print("ERROR: Could not load FLAIR volume")

# Ensure Markups module is available
try:
    slicer.modules.markups
    print("Markups module available for fiducial placement")
except:
    print("WARNING: Markups module may not be available")

print("")
print("Setup complete - ready for lesion localization task")
print("Use Markups > Fiducial to place a point at the tumor centroid")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with FLAIR volume..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_flair_volume.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window for optimal agent interaction
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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/lesion_localization_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Brain Lesion Localization Report"
echo "========================================"
echo ""
echo "You are given a brain MRI (FLAIR) showing a glioma."
echo "A neurosurgeon needs precise localization for surgical planning."
echo ""
echo "Your goal:"
echo "  1. Navigate through the FLAIR to find the hyperintense tumor"
echo "  2. Find the tumor's center (centroid of its 3D extent)"
echo "  3. Place a fiducial marker at the centroid (Markups > Fiducial)"
echo "  4. Note the RAS coordinates shown for the fiducial"
echo "  5. Capture screenshots of all 3 planes centered on the lesion"
echo "  6. Create a localization report JSON"
echo ""
echo "Save to ~/Documents/SlicerData/BraTS/LocalizationReport/:"
echo "  - lesion_axial.png"
echo "  - lesion_coronal.png"
echo "  - lesion_sagittal.png"
echo "  - lesion_centroid.mrk.json"
echo "  - localization_report.json"
echo ""