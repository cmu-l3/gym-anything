#!/bin/bash
echo "=== Setting up Spleen Volume Measurement Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Prepare AMOS abdominal CT data
echo "Preparing AMOS 2022 abdominal CT data..."
/workspace/scripts/prepare_amos_data.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE ($(du -h "$CT_FILE" | cut -f1))"

# Verify ground truth exists
GT_LABELS="$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz"
GT_JSON="$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json"

if [ ! -f "$GT_LABELS" ]; then
    echo "WARNING: Ground truth labels not found at $GT_LABELS"
fi

# Calculate spleen ground truth volume if not already done
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_spleen_gt.json" ]; then
    echo "Computing spleen ground truth..."
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

gt_labels_path = "$GT_LABELS"
gt_output_path = "$GROUND_TRUTH_DIR/${CASE_ID}_spleen_gt.json"

if os.path.exists(gt_labels_path):
    gt_nii = nib.load(gt_labels_path)
    gt_data = gt_nii.get_fdata()
    voxel_dims = gt_nii.header.get_zooms()[:3]
    voxel_vol_mm3 = float(np.prod(voxel_dims))
    
    # Spleen is label 1 in AMOS
    spleen_mask = (gt_data == 1)
    spleen_voxels = int(np.sum(spleen_mask))
    spleen_vol_ml = spleen_voxels * voxel_vol_mm3 / 1000.0
    
    # Get centroid for location verification
    if spleen_voxels > 0:
        coords = np.argwhere(spleen_mask)
        centroid = coords.mean(axis=0).tolist()
    else:
        centroid = [0, 0, 0]
    
    # Determine classification
    if spleen_vol_ml < 200:
        classification = "Normal"
    elif spleen_vol_ml < 400:
        classification = "Mild Splenomegaly"
    elif spleen_vol_ml < 800:
        classification = "Moderate Splenomegaly"
    else:
        classification = "Massive Splenomegaly"
    
    gt_info = {
        "case_id": "$CASE_ID",
        "spleen_voxels": spleen_voxels,
        "spleen_volume_ml": round(spleen_vol_ml, 2),
        "voxel_dims_mm": [float(v) for v in voxel_dims],
        "voxel_volume_mm3": round(voxel_vol_mm3, 4),
        "centroid_voxel": [round(c, 1) for c in centroid],
        "expected_classification": classification,
        "volume_shape": list(gt_data.shape)
    }
    
    with open(gt_output_path, "w") as f:
        json.dump(gt_info, f, indent=2)
    
    print(f"Spleen ground truth saved: {spleen_vol_ml:.1f} mL ({classification})")
else:
    print("No ground truth labels found - using synthetic data metrics")
    # For synthetic data, calculate expected values
    gt_info = {
        "case_id": "$CASE_ID",
        "spleen_volume_ml": 180.0,
        "expected_classification": "Normal",
        "note": "synthetic_data"
    }
    with open(gt_output_path, "w") as f:
        json.dump(gt_info, f, indent=2)
PYEOF
fi

# Record initial state - remove any previous outputs
echo "Cleaning previous task artifacts..."
rm -f "$AMOS_DIR/spleen_segmentation.nii.gz" 2>/dev/null || true
rm -f "$AMOS_DIR/spleen_segmentation.nii" 2>/dev/null || true
rm -f "$AMOS_DIR/spleen_report.json" 2>/dev/null || true
rm -f "$AMOS_DIR/Segmentation.nii.gz" 2>/dev/null || true
rm -f "/home/ga/Documents/SlicerData/Screenshots/spleen_*.png" 2>/dev/null || true

# Record that outputs don't exist at start
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "segmentation_exists": false,
    "report_exists": false,
    "case_id": "$CASE_ID",
    "ct_file": "$CT_FILE"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Create Slicer Python script to load CT with proper settings
cat > /tmp/load_amos_for_spleen.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT for spleen segmentation: {case_id}...")

# Load the CT volume
volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set abdominal soft tissue window/level (good for spleen visualization)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window: W=400, L=40
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background volume in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Navigate to approximate spleen location (left upper quadrant)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Center on upper abdomen where spleen is located
    center_x = (bounds[0] + bounds[1]) / 2
    center_y = (bounds[2] + bounds[3]) / 2
    # Spleen is in upper portion of scan
    upper_z = bounds[4] + (bounds[5] - bounds[4]) * 0.65
    
    # Set slice offsets
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":
            sliceNode.SetSliceOffset(upper_z)  # Axial - upper abdomen
        elif color == "Green":
            sliceNode.SetSliceOffset(center_y)  # Coronal
        else:
            sliceNode.SetSliceOffset(center_x + 30)  # Sagittal - offset left for spleen
    
    print(f"CT loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Window/Level set for soft tissue (W=400, L=40)")
    print(f"Navigated to upper left abdomen region")
else:
    print("ERROR: Could not load CT volume")

print("")
print("TASK: Segment the spleen and measure its volume")
print("The spleen is located in the left upper quadrant of the abdomen")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the setup script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_amos_for_spleen.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120

# Give extra time for volume to fully render
sleep 10

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
else
    echo "WARNING: Could not find Slicer window"
fi

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Spleen Volume Measurement for Splenomegaly Assessment"
echo "============================================================"
echo ""
echo "A patient presents with pancytopenia. Measure the spleen volume"
echo "to assess for splenomegaly."
echo ""
echo "Steps:"
echo "  1. Locate the spleen (left upper quadrant, lateral to stomach)"
echo "  2. Use Segment Editor to segment the spleen"
echo "  3. Calculate volume with Segment Statistics"
echo "  4. Classify: Normal (<200mL), Mild (200-400mL),"
echo "              Moderate (400-800mL), Massive (>800mL)"
echo ""
echo "Save outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/AMOS/spleen_segmentation.nii.gz"
echo "  - Report: ~/Documents/SlicerData/AMOS/spleen_report.json"
echo ""