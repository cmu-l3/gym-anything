#!/bin/bash
echo "=== Setting up Bilateral Kidney Volume Asymmetry Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

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
echo "CT volume found: $CT_FILE"

# Verify ground truth labels exist
GT_LABELS="$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz"
if [ ! -f "$GT_LABELS" ]; then
    echo "ERROR: Ground truth labels not found at $GT_LABELS"
    exit 1
fi
echo "Ground truth labels verified (hidden from agent)"

# Calculate ground truth kidney volumes for verification
echo "Computing ground truth kidney measurements..."
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
gt_dir = "$GROUND_TRUTH_DIR"
case_id = "$CASE_ID"

# Load ground truth labels
gt_nii = nib.load(gt_labels_path)
gt_data = gt_nii.get_fdata().astype(np.int32)
voxel_dims = gt_nii.header.get_zooms()[:3]
voxel_volume_mm3 = float(np.prod(voxel_dims))
voxel_volume_ml = voxel_volume_mm3 / 1000.0

# AMOS labels: 2 = right kidney, 3 = left kidney (anatomical convention)
left_kidney_mask = (gt_data == 3)
right_kidney_mask = (gt_data == 2)

left_volume_ml = float(np.sum(left_kidney_mask) * voxel_volume_ml)
right_volume_ml = float(np.sum(right_kidney_mask) * voxel_volume_ml)

# Calculate asymmetry
max_volume = max(left_volume_ml, right_volume_ml)
if max_volume > 0:
    asymmetry_pct = abs(left_volume_ml - right_volume_ml) / max_volume * 100
else:
    asymmetry_pct = 0.0

# Determine smaller kidney
if abs(left_volume_ml - right_volume_ml) < 1.0:
    smaller_kidney = "equal"
elif left_volume_ml < right_volume_ml:
    smaller_kidney = "left"
else:
    smaller_kidney = "right"

# Classification
if asymmetry_pct < 10:
    classification = "normal"
elif asymmetry_pct < 20:
    classification = "mild"
elif asymmetry_pct < 30:
    classification = "significant"
else:
    classification = "severe"

# Save ground truth
gt_info = {
    "case_id": case_id,
    "left_kidney_volume_ml": round(left_volume_ml, 2),
    "right_kidney_volume_ml": round(right_volume_ml, 2),
    "left_kidney_voxels": int(np.sum(left_kidney_mask)),
    "right_kidney_voxels": int(np.sum(right_kidney_mask)),
    "asymmetry_percentage": round(asymmetry_pct, 2),
    "smaller_kidney": smaller_kidney,
    "classification": classification,
    "voxel_volume_ml": voxel_volume_ml,
    "voxel_dims_mm": [float(v) for v in voxel_dims]
}

gt_path = os.path.join(gt_dir, f"{case_id}_kidney_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_info, f, indent=2)

print(f"Ground truth kidney measurements:")
print(f"  Left kidney: {left_volume_ml:.1f} mL ({np.sum(left_kidney_mask)} voxels)")
print(f"  Right kidney: {right_volume_ml:.1f} mL ({np.sum(right_kidney_mask)} voxels)")
print(f"  Asymmetry: {asymmetry_pct:.1f}%")
print(f"  Smaller kidney: {smaller_kidney}")
print(f"  Classification: {classification}")
print(f"Saved to: {gt_path}")
PYEOF

# Record initial state - remove any previous outputs
echo "Clearing previous outputs..."
rm -f "$AMOS_DIR/kidney_segmentation.seg.nrrd" 2>/dev/null || true
rm -f "$AMOS_DIR/kidney_segmentation.nii.gz" 2>/dev/null || true
rm -f "$AMOS_DIR/kidney_asymmetry_report.json" 2>/dev/null || true
rm -f /tmp/kidney_task_result.json 2>/dev/null || true

# Create a Slicer Python script to load the CT with optimal settings
cat > /tmp/load_kidney_ct.py << 'PYEOF'
import slicer
import os

ct_path = os.environ.get("CT_FILE", "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz")
case_id = os.environ.get("CASE_ID", "amos_0001")

print(f"Loading abdominal CT scan: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set optimal window/level for kidney visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window good for kidneys
        displayNode.SetWindow(350)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to kidney level (approximately L1-L3)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Center on data, focus on kidney region
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        
        # Adjust to kidney level (approximately middle third of abdomen)
        if color == "Red":  # Axial
            kidney_level = center[2] * 0.6  # Upper-mid abdomen
            sliceNode.SetSliceOffset(kidney_level)
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with soft tissue window (W=350, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("")
    print("Navigate to find both kidneys (bilateral retroperitoneal organs)")
    print("Kidneys appear as bean-shaped structures lateral to the spine")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for kidney segmentation task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with environment variables
echo "Launching 3D Slicer with abdominal CT..."
export CT_FILE CASE_ID
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" CASE_ID="$CASE_ID" /opt/Slicer/Slicer --python-script /tmp/load_kidney_ct.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/kidney_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Bilateral Kidney Volume Asymmetry Assessment"
echo "===================================================="
echo ""
echo "Clinical Context:"
echo "  A nephrologist suspects unilateral renal disease in a patient"
echo "  with hypertension. Significant kidney volume asymmetry (>20%)"
echo "  may indicate chronic disease affecting one kidney."
echo ""
echo "Your goal:"
echo "  1. Locate BOTH kidneys in the abdominal CT"
echo "  2. Create a segmentation with TWO separate segments:"
echo "     - 'Left Kidney'"  
echo "     - 'Right Kidney'"
echo "  3. Use Segment Statistics to calculate each kidney's volume (mL)"
echo "  4. Calculate asymmetry: |Left - Right| / max(Left, Right) × 100%"
echo "  5. Classify: Normal (<10%), Mild (10-20%), Significant (20-30%), Severe (>30%)"
echo ""
echo "Save your outputs:"
echo "  - Segmentation: ~/Documents/SlicerData/AMOS/kidney_segmentation.seg.nrrd"
echo "  - Report JSON: ~/Documents/SlicerData/AMOS/kidney_asymmetry_report.json"
echo ""