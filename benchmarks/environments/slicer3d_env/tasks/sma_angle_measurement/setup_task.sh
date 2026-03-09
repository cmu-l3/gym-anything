#!/bin/bash
echo "=== Setting up SMA Angle Measurement Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Setup directories
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare AMOS data (downloads real data or generates synthetic with SMA)
echo "Preparing abdominal CT data..."
export AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "amos_0001"

# Get the case ID used
CASE_ID="amos_0001"
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

# Generate SMA-specific ground truth
echo "Computing SMA angle ground truth..."
python3 << 'PYEOF'
import os
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

# Check for case ID
case_id = "amos_0001"
if os.path.exists("/tmp/amos_case_id"):
    with open("/tmp/amos_case_id") as f:
        case_id = f.read().strip()

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
gt_labels_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

# Load CT
if os.path.exists(ct_path):
    ct_nii = nib.load(ct_path)
    ct_data = ct_nii.get_fdata()
    spacing = ct_nii.header.get_zooms()[:3]
    
    # Default ground truth for synthetic case
    # SMA angle is typically 38-65 degrees normally
    # For this task, we create a borderline case (angle ~40 degrees)
    sma_gt = {
        "case_id": case_id,
        "sma_angle_degrees": 40.0,
        "sma_angle_tolerance": 5.0,
        "aortomesenteric_distance_mm": 9.5,
        "distance_tolerance_mm": 3.0,
        "expected_classification": "borderline",
        "sma_origin_ras": [0.0, 20.0, 137.5],  # Approximate RAS coordinates
        "aorta_position_ras": [0.0, 40.0, 137.5],
        "measurement_plane": "sagittal",
        "physiological_range": {"min": 5, "max": 90},
        "notes": "Borderline SMA angle case for syndrome screening"
    }
    
    # Try to refine from actual label data if available
    if os.path.exists(gt_labels_path):
        label_nii = nib.load(gt_labels_path)
        label_data = label_nii.get_fdata()
        
        # Find aorta centroid (label 10 in AMOS)
        aorta_mask = (label_data == 10)
        if np.any(aorta_mask):
            aorta_coords = np.argwhere(aorta_mask)
            aorta_centroid = aorta_coords.mean(axis=0)
            
            # Find upper portion of aorta where SMA originates
            z_upper_third = int(label_data.shape[2] * 0.55)
            aorta_upper = aorta_coords[aorta_coords[:, 2] > z_upper_third]
            
            if len(aorta_upper) > 0:
                aorta_upper_centroid = aorta_upper.mean(axis=0)
                
                # Convert to RAS coordinates
                affine = ct_nii.affine
                ijk_aorta = np.append(aorta_upper_centroid, 1)
                ras_aorta = affine.dot(ijk_aorta)[:3]
                
                # SMA origin is anterior to aorta
                sma_origin_ras = ras_aorta.copy()
                sma_origin_ras[1] -= 20  # Anterior direction
                
                sma_gt["sma_origin_ras"] = [float(x) for x in sma_origin_ras]
                sma_gt["aorta_position_ras"] = [float(x) for x in ras_aorta]
                
                print(f"Refined SMA origin estimate (RAS): {sma_gt['sma_origin_ras']}")
    
    # Save ground truth
    gt_path = os.path.join(gt_dir, f"{case_id}_sma_gt.json")
    with open(gt_path, 'w') as f:
        json.dump(sma_gt, f, indent=2)
    print(f"SMA ground truth saved to: {gt_path}")
    print(f"  Expected angle: {sma_gt['sma_angle_degrees']}° ± {sma_gt['sma_angle_tolerance']}°")
    print(f"  Expected distance: {sma_gt['aortomesenteric_distance_mm']}mm")
    print(f"  Expected classification: {sma_gt['expected_classification']}")
else:
    print(f"ERROR: CT file not found at {ct_path}")
    exit(1)
PYEOF

# Clean up any previous agent outputs
echo "Cleaning previous outputs..."
rm -f "$AMOS_DIR/sma_angle.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/sma_report.json" 2>/dev/null || true

# Record initial state
cat > /tmp/sma_initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "case_id": "$CASE_ID",
    "ct_file": "$CT_FILE",
    "markup_existed": false,
    "report_existed": false
}
EOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Slicer Python script to load the CT with proper settings
cat > /tmp/load_sma_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT scan for SMA angle measurement...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set vascular window/level (good for seeing vessels)
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Window/level optimized for vascular structures
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Center on data at upper abdominal level (where SMA originates)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Position views to show upper abdomen where SMA originates
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        # Center coordinates - focus on upper abdomen
        center_x = (bounds[0] + bounds[1]) / 2
        center_y = (bounds[2] + bounds[3]) / 2
        center_z = bounds[4] + (bounds[5] - bounds[4]) * 0.55  # Upper portion
        
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center_z)
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center_y)
        else:  # Yellow - Sagittal (best for SMA angle)
            sliceNode.SetSliceOffset(center_x)
    
    print(f"CT loaded with vascular window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print("Tip: Use sagittal view (Yellow) to best visualize SMA angle")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for SMA angle measurement task")
PYEOF

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_sma_ct.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/sma_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Superior Mesenteric Artery (SMA) Angle Measurement"
echo "========================================================="
echo ""
echo "A 22-year-old thin woman presents with postprandial pain,"
echo "nausea, and 15-pound weight loss. Evaluate for SMA syndrome."
echo ""
echo "Your goal:"
echo "  1. Navigate to the SMA origin (upper abdomen, ~L1 level)"
echo "  2. Find sagittal view showing aorta and SMA together"
echo "  3. Measure aortomesenteric angle using Markups angle tool"
echo "  4. Measure aortomesenteric distance"
echo "  5. Classify findings (normal/borderline/sma_syndrome_likely)"
echo ""
echo "Classification criteria:"
echo "  - Normal: angle 38-65°, distance >10mm"
echo "  - Borderline: angle 25-38°, distance 8-10mm"
echo "  - SMA syndrome likely: angle <25°, distance <8mm"
echo ""
echo "Save outputs to:"
echo "  - ~/Documents/SlicerData/AMOS/sma_angle.mrk.json"
echo "  - ~/Documents/SlicerData/AMOS/sma_report.json"
echo ""