#!/bin/bash
echo "=== Setting up Common Bile Duct Measurement Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Prepare AMOS data (downloads real data or generates synthetic with porta hepatis anatomy)
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

# Record initial state and task start time
rm -f /tmp/cbd_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/cbd_measurement.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/cbd_report.json" 2>/dev/null || true
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Generate ground truth CBD information based on anatomy
# The CBD is located at the porta hepatis, anterior to the portal vein
echo "Generating CBD reference data..."
python3 << 'PYEOF'
import os
import sys
import json

try:
    import numpy as np
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy", "nibabel"])
    import numpy as np
    import nibabel as nib

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
labels_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

# Load CT and labels if available
ct_img = nib.load(ct_path)
ct_data = ct_img.get_fdata()
spacing = ct_img.header.get_zooms()[:3]

# Try to load labels to find liver location (porta hepatis reference)
liver_centroid = None
porta_hepatis_region = None

if os.path.exists(labels_path):
    labels_img = nib.load(labels_path)
    labels = labels_img.get_fdata()
    
    # AMOS labels: 6 = liver
    liver_mask = (labels == 6)
    if np.any(liver_mask):
        liver_coords = np.argwhere(liver_mask)
        liver_centroid = liver_coords.mean(axis=0)
        
        # Porta hepatis is at the inferior-medial aspect of the liver
        # Approximate as the inferior 20% of liver, medial side
        z_min = liver_coords[:, 2].min()
        z_range = liver_coords[:, 2].max() - z_min
        inferior_thresh = z_min + z_range * 0.3
        
        inferior_liver = liver_coords[liver_coords[:, 2] < inferior_thresh]
        if len(inferior_liver) > 0:
            porta_hepatis_region = inferior_liver.mean(axis=0)
        else:
            porta_hepatis_region = liver_centroid

# Estimate CBD location and expected diameter
# CBD is typically 4-6mm in normal patients
# The synthetic data may have a defined CBD or we estimate from anatomy

cbd_info = {
    "case_id": case_id,
    "ct_shape": list(ct_data.shape),
    "voxel_spacing_mm": [float(s) for s in spacing],
}

if porta_hepatis_region is not None:
    cbd_info["porta_hepatis_region_voxels"] = [float(x) for x in porta_hepatis_region]
    cbd_info["porta_hepatis_region_mm"] = [float(x * s) for x, s in zip(porta_hepatis_region, spacing)]
    
    # Expected CBD is anterior to this point
    # CBD diameter estimate (normal range)
    cbd_info["expected_cbd_diameter_mm"] = 5.0  # Normal average
    cbd_info["expected_cbd_range_mm"] = [3.0, 8.0]
    
if liver_centroid is not None:
    cbd_info["liver_centroid_voxels"] = [float(x) for x in liver_centroid]

# Normal CBD classification thresholds
cbd_info["classification_thresholds"] = {
    "normal_max_mm": 6.0,
    "borderline_max_mm": 8.0,
    "dilated_above_mm": 8.0
}

# Save CBD reference info
gt_path = os.path.join(gt_dir, f"{case_id}_cbd_gt.json")
with open(gt_path, "w") as f:
    json.dump(cbd_info, f, indent=2)

print(f"CBD reference data saved to {gt_path}")
print(f"Porta hepatis region: {cbd_info.get('porta_hepatis_region_mm', 'Not determined')}")
PYEOF

# Create a Slicer Python script to load the CT with appropriate window/level
cat > /tmp/load_cbd_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT scan for CBD assessment: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set soft tissue window for optimal bile duct visualization
    # Standard soft tissue: W=400, L=40
    # For bile ducts, slightly narrower window helps: W=350, L=50
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(350)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to approximate porta hepatis level
    # This is typically in the upper abdomen, around slice 60-70% from inferior
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Calculate approximate porta hepatis location
    z_range = bounds[5] - bounds[4]
    porta_z = bounds[4] + z_range * 0.65  # Upper abdomen
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        
        if color == "Red":  # Axial view - set to porta hepatis level
            sliceNode.SetSliceOffset(porta_z)
        elif color == "Green":  # Coronal view
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal view
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with soft tissue window (W=350, L=50)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Initial axial view set to approximate porta hepatis level (z={porta_z:.1f})")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for CBD measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_cbd_ct.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/cbd_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Common Bile Duct (CBD) Diameter Measurement"
echo "=================================================="
echo ""
echo "Clinical Scenario:"
echo "  The patient presents with right upper quadrant pain and elevated"
echo "  liver enzymes. You need to assess the CBD for possible obstruction."
echo ""
echo "Your goal:"
echo "  1. Navigate to the porta hepatis (liver hilum)"
echo "  2. Identify the portal triad (portal vein, CBD, hepatic artery)"
echo "  3. The CBD is anterior/lateral to the portal vein (low attenuation)"
echo "  4. Measure the internal diameter of the CBD"
echo "  5. Create a report with your findings"
echo ""
echo "Classification:"
echo "  - Normal: ≤ 6mm"
echo "  - Borderline: 7-8mm"
echo "  - Dilated: > 8mm"
echo ""
echo "Save your outputs:"
echo "  - Measurement: ~/Documents/SlicerData/AMOS/cbd_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/cbd_report.json"
echo ""