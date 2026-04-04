#!/bin/bash
echo "=== Setting up Gastric Volume Estimation Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 abdominal CT data..."
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
echo "CT volume found: $CT_FILE ($(du -h "$CT_FILE" | cut -f1))"

# Verify ground truth exists
GT_LABELS="$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz"
GT_JSON="$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json"

if [ ! -f "$GT_LABELS" ]; then
    echo "WARNING: Ground truth labels not found at $GT_LABELS"
fi

# Extract stomach-specific ground truth for verification
echo "Preparing stomach ground truth..."
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

gt_dir = "$GROUND_TRUTH_DIR"
case_id = "$CASE_ID"
labels_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

if not os.path.exists(labels_path):
    print(f"Ground truth labels not found: {labels_path}")
    sys.exit(0)

print(f"Loading ground truth labels from {labels_path}")
label_nii = nib.load(labels_path)
label_data = label_nii.get_fdata().astype(np.int16)
voxel_dims = label_nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))

# AMOS label 9 = stomach
stomach_mask = (label_data == 9)
stomach_voxels = int(np.sum(stomach_mask))
stomach_volume_mm3 = stomach_voxels * voxel_volume_mm3
stomach_volume_ml = stomach_volume_mm3 / 1000.0

# Calculate bounding box
if np.any(stomach_mask):
    coords = np.argwhere(stomach_mask)
    min_coords = coords.min(axis=0)
    max_coords = coords.max(axis=0)
    bbox = {
        "min": min_coords.tolist(),
        "max": max_coords.tolist(),
        "center": ((min_coords + max_coords) / 2).tolist()
    }
else:
    bbox = {"min": [0,0,0], "max": [0,0,0], "center": [0,0,0]}

# Classify stomach size
if stomach_volume_ml < 400:
    classification = "Small"
elif stomach_volume_ml < 1000:
    classification = "Normal"
elif stomach_volume_ml < 1500:
    classification = "Enlarged"
else:
    classification = "Markedly_enlarged"

# Check for adjacent organs (for spillover detection later)
liver_voxels = int(np.sum(label_data == 6))
spleen_voxels = int(np.sum(label_data == 1))

gt_info = {
    "case_id": case_id,
    "stomach_voxels": stomach_voxels,
    "stomach_volume_mm3": stomach_volume_mm3,
    "stomach_volume_ml": round(stomach_volume_ml, 2),
    "classification": classification,
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "voxel_volume_mm3": voxel_volume_mm3,
    "bounding_box": bbox,
    "liver_voxels": liver_voxels,
    "spleen_voxels": spleen_voxels
}

gt_path = os.path.join(gt_dir, f"{case_id}_stomach_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_info, f, indent=2)

print(f"Stomach ground truth saved to {gt_path}")
print(f"  Volume: {stomach_volume_ml:.2f} mL")
print(f"  Classification: {classification}")
print(f"  Voxels: {stomach_voxels}")
PYEOF

# Record initial state - clean up any previous outputs
echo "Cleaning up previous task outputs..."
rm -f /tmp/gastric_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/gastric_segmentation.nii.gz" 2>/dev/null || true
rm -f "$AMOS_DIR/bariatric_report.json" 2>/dev/null || true

# Create a Slicer Python script to load the CT with appropriate settings
cat > /tmp/load_amos_gastric.py << 'PYEOF'
import slicer
import os
import sys

ct_path = sys.argv[1] if len(sys.argv) > 1 else "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz"
case_id = os.path.basename(ct_path).replace(".nii.gz", "")

print(f"Loading abdominal CT for gastric volume estimation: {case_id}")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set abdominal soft tissue window/level for optimal stomach visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window: W=400, L=40 (good for stomach visualization)
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Get volume bounds for centering
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Position slices to show upper abdomen (where stomach is located)
    # Stomach is typically in the left upper quadrant
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        # Calculate centers with bias toward upper abdomen
        center_x = (bounds[0] + bounds[1]) / 2
        center_y = (bounds[2] + bounds[3]) / 2
        center_z = bounds[4] + (bounds[5] - bounds[4]) * 0.6  # Upper portion
        
        if color == "Red":  # Axial - show slice through stomach area
            sliceNode.SetSliceOffset(center_z)
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center_y)
        else:  # Sagittal - bias toward left side where stomach is
            sliceNode.SetSliceOffset(center_x + (bounds[1] - bounds[0]) * 0.15)
    
    print(f"CT loaded with soft tissue window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Views positioned to show upper abdomen")
else:
    print("ERROR: Could not load CT volume")

print("Setup complete - ready for gastric segmentation task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_amos_gastric.py "$CT_FILE" > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/gastric_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Gastric Volume Estimation for Bariatric Surgery Planning"
echo "================================================================"
echo ""
echo "You are given an abdominal CT scan of a patient being evaluated"
echo "for bariatric surgery (sleeve gastrectomy)."
echo ""
echo "Your goal:"
echo "  1. Locate the stomach (left upper quadrant, under diaphragm)"
echo "  2. Use Segment Editor to segment the entire stomach"
echo "  3. Include fundus, body, and antrum; exclude esophagus/duodenum"
echo "  4. Use Segment Statistics to measure volume in mL"
echo "  5. Classify: Small (<400mL), Normal (400-1000mL),"
echo "     Enlarged (1000-1500mL), Markedly_enlarged (>1500mL)"
echo ""
echo "Save your outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/AMOS/gastric_segmentation.nii.gz"
echo "  - Report: ~/Documents/SlicerData/AMOS/bariatric_report.json"
echo ""
echo "Report JSON should contain:"
echo "  - volume_ml: measured volume"
echo "  - classification: size category"
echo "  - fundus_included: true/false"
echo "  - surgical_recommendation: brief recommendation"
echo ""