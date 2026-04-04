#!/bin/bash
echo "=== Setting up Diaphragm Dome Assessment Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Ensure directories exist
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS CT data..."
export CASE_ID GROUND_TRUTH_DIR AMOS_DIR
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

# Generate diaphragm position ground truth from segmentation labels
echo "Generating diaphragm position ground truth..."
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

case_id = "$CASE_ID"
gt_dir = "$GROUND_TRUTH_DIR"
amos_dir = "$AMOS_DIR"

# Load label map
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
if not os.path.exists(label_path):
    print(f"WARNING: Label file not found: {label_path}")
    print("Creating synthetic ground truth...")
    # Load CT to get dimensions
    ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
    ct_nii = nib.load(ct_path)
    ct_shape = ct_nii.shape
    spacing = ct_nii.header.get_zooms()[:3]
    
    # Create synthetic diaphragm positions
    total_height = ct_shape[2] * spacing[2]
    right_dome_z = total_height * 0.7
    left_dome_z = total_height * 0.65
    
    gt_data = {
        "case_id": case_id,
        "right_dome_z_mm": round(right_dome_z, 1),
        "right_dome_vertebral_level": "T10",
        "left_dome_z_mm": round(left_dome_z, 1),
        "left_dome_vertebral_level": "T11",
        "height_difference_mm": round(right_dome_z - left_dome_z, 1),
        "vertebral_level_difference": 1,
        "right_higher_than_left": True,
        "is_normal": True,
        "expected_interpretation": "Normal diaphragm position and symmetry",
        "spacing_mm": [float(s) for s in spacing],
        "volume_shape": list(ct_shape)
    }
else:
    labels = nib.load(label_path)
    data = labels.get_fdata().astype(np.int32)
    affine = labels.affine
    spacing = labels.header.get_zooms()[:3]
    
    print(f"Loaded labels: shape={data.shape}, spacing={spacing}")
    
    # AMOS labels: 1=spleen, 6=liver, 7=stomach
    # Find right hemidiaphragm dome (superior extent of liver, label 6)
    liver_mask = (data == 6)
    right_dome_z = None
    right_dome_center = None
    
    if np.any(liver_mask):
        liver_coords = np.argwhere(liver_mask)
        max_z_idx = np.argmax(liver_coords[:, 2])
        right_dome_voxel = liver_coords[max_z_idx]
        max_z = right_dome_voxel[2]
        top_liver = liver_coords[liver_coords[:, 2] >= max_z - 3]
        right_dome_center = top_liver.mean(axis=0)
        right_dome_z = float(right_dome_center[2] * spacing[2])
        print(f"Right dome (from liver): Z={right_dome_z:.1f}mm")
    
    # Find left hemidiaphragm dome (superior extent of spleen/stomach)
    left_organs = (data == 1) | (data == 7)
    left_dome_z = None
    left_dome_center = None
    
    if np.any(left_organs):
        left_coords = np.argwhere(left_organs)
        max_z_idx = np.argmax(left_coords[:, 2])
        left_dome_voxel = left_coords[max_z_idx]
        max_z = left_dome_voxel[2]
        top_left = left_coords[left_coords[:, 2] >= max_z - 3]
        left_dome_center = top_left.mean(axis=0)
        left_dome_z = float(left_dome_center[2] * spacing[2])
        print(f"Left dome (from spleen/stomach): Z={left_dome_z:.1f}mm")
    
    # Fallback if organs not found
    if right_dome_z is None:
        nz = data.shape[2]
        right_dome_z = float(nz * 0.7 * spacing[2])
    if left_dome_z is None:
        nz = data.shape[2]
        left_dome_z = float(nz * 0.65 * spacing[2])
    
    # Calculate difference
    height_diff = right_dome_z - left_dome_z
    
    # Estimate vertebral levels
    total_height = data.shape[2] * spacing[2]
    mid_z = total_height / 2
    
    def z_to_vertebral_level(z_mm, mid_z):
        offset_from_mid = z_mm - mid_z
        vertebra_offset = int(offset_from_mid / 25)
        if vertebra_offset >= 4:
            return "T8"
        elif vertebra_offset == 3:
            return "T9"
        elif vertebra_offset == 2:
            return "T10"
        elif vertebra_offset == 1:
            return "T11"
        elif vertebra_offset == 0:
            return "T12"
        elif vertebra_offset == -1:
            return "L1"
        elif vertebra_offset == -2:
            return "L2"
        else:
            return "L3"
    
    right_level = z_to_vertebral_level(right_dome_z, mid_z)
    left_level = z_to_vertebral_level(left_dome_z, mid_z)
    
    # Calculate level difference
    level_order = ["T8", "T9", "T10", "T11", "T12", "L1", "L2", "L3", "L4"]
    try:
        right_idx = level_order.index(right_level)
        left_idx = level_order.index(left_level)
        level_diff = left_idx - right_idx
    except ValueError:
        level_diff = 0
    
    # Clinical interpretation
    if abs(height_diff) < 30 and abs(level_diff) <= 2:
        interpretation = "Normal diaphragm position and symmetry"
        normal = True
    elif height_diff > 30:
        interpretation = "Elevated right hemidiaphragm - consider hepatomegaly or right phrenic nerve palsy"
        normal = False
    elif height_diff < -30:
        interpretation = "Elevated left hemidiaphragm - consider left phrenic nerve palsy"
        normal = False
    else:
        interpretation = "Mild asymmetry, likely normal variant"
        normal = True
    
    gt_data = {
        "case_id": case_id,
        "right_dome_z_mm": round(right_dome_z, 1),
        "right_dome_vertebral_level": right_level,
        "right_dome_center_voxel": [float(x) for x in right_dome_center] if right_dome_center is not None else None,
        "left_dome_z_mm": round(left_dome_z, 1),
        "left_dome_vertebral_level": left_level,
        "left_dome_center_voxel": [float(x) for x in left_dome_center] if left_dome_center is not None else None,
        "height_difference_mm": round(height_diff, 1),
        "vertebral_level_difference": level_diff,
        "right_higher_than_left": height_diff > 0,
        "is_normal": normal,
        "expected_interpretation": interpretation,
        "spacing_mm": [float(s) for s in spacing],
        "volume_shape": list(data.shape)
    }

# Save ground truth
gt_path = os.path.join(gt_dir, f"{case_id}_diaphragm_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"Right dome: {gt_data['right_dome_vertebral_level']} ({gt_data['right_dome_z_mm']:.1f}mm)")
print(f"Left dome: {gt_data['left_dome_vertebral_level']} ({gt_data['left_dome_z_mm']:.1f}mm)")
print(f"Difference: {gt_data['height_difference_mm']:.1f}mm ({gt_data['vertebral_level_difference']} levels)")
print(f"Interpretation: {gt_data['expected_interpretation']}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_diaphragm_gt.json" ]; then
    echo "ERROR: Ground truth generation failed!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Clean up any previous agent outputs
rm -f "$AMOS_DIR/diaphragm_markers.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/diaphragm_report.json" 2>/dev/null || true

# Create a Slicer Python script to load the CT with optimal settings
cat > /tmp/load_diaphragm_ct.py << 'PYEOF'
import slicer
import os

ct_path = os.environ.get("CT_FILE", "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz")
case_id = os.environ.get("CASE_ID", "amos_0001")

print(f"Loading CT scan: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("ChestAbdomenCT")
    
    # Set default soft tissue window for diaphragm visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center views on the diaphragm region (approximately upper-middle of volume)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        # Position at approximately 60-70% of height (diaphragm region)
        center_x = (bounds[0] + bounds[1]) / 2
        center_y = (bounds[2] + bounds[3]) / 2
        z_range = bounds[5] - bounds[4]
        diaphragm_z = bounds[4] + z_range * 0.65
        
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(diaphragm_z)
        elif color == "Green":  # Coronal - good for dome visualization
            sliceNode.SetSliceOffset(center_y)
        else:  # Sagittal
            sliceNode.SetSliceOffset(center_x)
    
    print(f"CT loaded with soft tissue window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("Views centered on diaphragm region")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for diaphragm assessment task")
PYEOF

# Export variables for Python script
export CT_FILE CASE_ID

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with CT scan..."
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" CASE_ID="$CASE_ID" /opt/Slicer/Slicer --python-script /tmp/load_diaphragm_ct.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/diaphragm_task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Diaphragm Position and Symmetry Assessment"
echo "================================================="
echo ""
echo "You are given a CT scan. Assess the diaphragm position."
echo ""
echo "Your goal:"
echo "  1. Navigate to identify BOTH hemidiaphragm domes"
echo "  2. Place fiducial markers at each dome apex"
echo "     - Label: 'Right' or 'R' for right dome"
echo "     - Label: 'Left' or 'L' for left dome"
echo "  3. Determine vertebral level for each dome"
echo "  4. Measure vertical height difference (mm)"
echo "  5. Assess contour (smooth vs irregular)"
echo "  6. Provide clinical interpretation"
echo ""
echo "Normal reference:"
echo "  - Right dome typically 1-2cm higher than left"
echo "  - Asymmetry >3cm suggests pathology"
echo ""
echo "Save outputs:"
echo "  - Markers: ~/Documents/SlicerData/AMOS/diaphragm_markers.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/diaphragm_report.json"
echo ""