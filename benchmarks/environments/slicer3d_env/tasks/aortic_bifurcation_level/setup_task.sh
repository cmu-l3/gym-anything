#!/bin/bash
echo "=== Setting up Aortic Bifurcation Level Identification Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 data..."
export CASE_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Clear previous task outputs
echo "Clearing previous task outputs..."
rm -f /tmp/bifurcation_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/bifurcation_marker.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/bifurcation_report.json" 2>/dev/null || true

# Compute bifurcation ground truth from aorta segmentation
echo "Computing bifurcation ground truth..."
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

from scipy.ndimage import label as scipy_label

case_id = "$CASE_ID"
gt_dir = "$GROUND_TRUTH_DIR"
amos_dir = "$AMOS_DIR"

# Load aorta ground truth
gt_path = os.path.join(gt_dir, f"{case_id}_aorta_gt.json")
with open(gt_path) as f:
    gt_data = json.load(f)

# Load label map
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
if not os.path.exists(label_path):
    print(f"Label file not found: {label_path}")
    sys.exit(1)

label_nii = nib.load(label_path)
label_data = label_nii.get_fdata().astype(np.int16)
affine = label_nii.affine
voxel_spacing = label_nii.header.get_zooms()[:3]

# Extract aorta mask (label 10)
aorta_mask = (label_data == 10)

if not np.any(aorta_mask):
    print("No aorta voxels found!")
    sys.exit(1)

# Find bifurcation by scanning from inferior to superior
# Look for where a single connected component becomes two
nz = label_data.shape[2]
bifurcation_z = None
bifurcation_xy = None

for z in range(nz - 1, -1, -1):  # Start from most inferior slice
    slice_mask = aorta_mask[:, :, z]
    if not np.any(slice_mask):
        continue
    
    labeled_slice, num_components = scipy_label(slice_mask)
    
    if num_components == 1:
        # Found single component - this is at or above bifurcation
        # The bifurcation is approximately here
        bifurcation_z = z
        
        # Find centroid of the single component
        coords = np.argwhere(slice_mask)
        centroid = coords.mean(axis=0)
        bifurcation_xy = centroid
        break

if bifurcation_z is None:
    # Fallback: use most inferior aorta slice
    z_coords = np.where(np.any(aorta_mask, axis=(0, 1)))[0]
    if len(z_coords) > 0:
        bifurcation_z = z_coords.min()
        slice_mask = aorta_mask[:, :, bifurcation_z]
        coords = np.argwhere(slice_mask)
        bifurcation_xy = coords.mean(axis=0) if len(coords) > 0 else [label_data.shape[0]//2, label_data.shape[1]//2]

# Convert to RAS coordinates
ijk_coords = np.array([bifurcation_xy[0], bifurcation_xy[1], bifurcation_z, 1])
ras_coords = affine.dot(ijk_coords)[:3]

# Determine vertebral level based on z-coordinate
total_z_mm = nz * voxel_spacing[2]
z_mm = bifurcation_z * voxel_spacing[2]
z_fraction = z_mm / total_z_mm if total_z_mm > 0 else 0.5

# Typical abdominal CT: bifurcation usually at L4 level
# Map z-fraction to vertebral level (assuming scan covers T12-S1 range)
if z_fraction < 0.15:
    vertebral_level = "S1"
elif z_fraction < 0.30:
    vertebral_level = "L5"
elif z_fraction < 0.45:
    vertebral_level = "L4"
elif z_fraction < 0.60:
    vertebral_level = "L3"
elif z_fraction < 0.75:
    vertebral_level = "L2"
elif z_fraction < 0.90:
    vertebral_level = "L1"
else:
    vertebral_level = "T12"

# Measure terminal aortic diameter at bifurcation level
# Use area-equivalent diameter
slice_mask = aorta_mask[:, :, min(bifurcation_z + 5, nz - 1)]  # Slightly above bifurcation
area_pixels = np.sum(slice_mask)
area_mm2 = area_pixels * voxel_spacing[0] * voxel_spacing[1]
terminal_diameter = 2 * np.sqrt(area_mm2 / np.pi) if area_mm2 > 0 else 0

# Save bifurcation ground truth
bifurcation_gt = {
    "case_id": case_id,
    "bifurcation_coords_ras": [float(x) for x in ras_coords],
    "bifurcation_coords_ijk": [float(bifurcation_xy[0]), float(bifurcation_xy[1]), float(bifurcation_z)],
    "bifurcation_z_slice": int(bifurcation_z),
    "vertebral_level": vertebral_level,
    "terminal_diameter_mm": float(terminal_diameter),
    "voxel_spacing_mm": [float(x) for x in voxel_spacing],
    "z_fraction": float(z_fraction)
}

bifurcation_gt_path = os.path.join(gt_dir, f"{case_id}_bifurcation_gt.json")
with open(bifurcation_gt_path, "w") as f:
    json.dump(bifurcation_gt, f, indent=2)

print(f"Bifurcation ground truth saved: {bifurcation_gt_path}")
print(f"  RAS coordinates: {ras_coords}")
print(f"  Vertebral level: {vertebral_level}")
print(f"  Terminal diameter: {terminal_diameter:.1f} mm")
PYEOF

# Create a Slicer Python script to load the CT
cat > /tmp/load_amos_ct_bifurcation.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading AMOS CT scan for bifurcation task: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")

    # Set default abdominal window/level
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Standard soft tissue window for abdominal CT
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())

    slicer.util.resetSliceViews()

    # Center on data - position at lower abdomen where bifurcation typically is
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Start at approximately the lower third of the volume (where bifurcation usually is)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        if color == "Red":  # Axial view - position in lower abdomen
            z_range = bounds[5] - bounds[4]
            lower_z = bounds[4] + z_range * 0.3  # Lower third
            sliceNode.SetSliceOffset(lower_z)
        elif color == "Green":  # Coronal view
            center_y = (bounds[2] + bounds[3]) / 2
            sliceNode.SetSliceOffset(center_y)
        else:  # Sagittal view
            center_x = (bounds[0] + bounds[1]) / 2
            sliceNode.SetSliceOffset(center_x)

    print(f"CT loaded with abdominal window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("Starting position: lower abdomen (near typical bifurcation level)")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for aortic bifurcation identification task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_amos_ct_bifurcation.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/bifurcation_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Aortic Bifurcation Level Identification"
echo "=============================================="
echo ""
echo "You are given an abdominal CT scan. Identify the aortic bifurcation -"
echo "where the abdominal aorta divides into left and right iliac arteries."
echo ""
echo "Your tasks:"
echo "  1. Navigate through axial slices to find the aorta"
echo "  2. Scroll inferiorly to find where it bifurcates (splits into two)"
echo "  3. Place a fiducial marker at the bifurcation point"
echo "  4. Identify the corresponding vertebral level (L3, L4, L5, or S1)"
echo "  5. Measure the aortic diameter just above the bifurcation"
echo ""
echo "Save your outputs:"
echo "  - Fiducial: ~/Documents/SlicerData/AMOS/bifurcation_marker.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/bifurcation_report.json"
echo ""
echo "Report JSON format:"
echo '  {"vertebral_level": "L4", "coordinates": {...}, "terminal_diameter_mm": 18.5}'
echo ""