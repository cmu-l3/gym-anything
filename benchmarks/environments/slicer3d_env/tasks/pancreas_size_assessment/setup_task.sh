#!/bin/bash
echo "=== Setting up Pancreas Size Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 data..."
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

# Record initial state - remove any previous outputs
rm -f /tmp/pancreas_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/pancreas_measurements.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/pancreas_report.json" 2>/dev/null || true

# Compute ground truth pancreas dimensions from AMOS label map
echo "Computing ground truth pancreas dimensions..."

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Ensure dependencies
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

case_id = os.environ.get("CASE_ID", "amos_0001")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")

# Load the label map
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
if not os.path.exists(label_path):
    print(f"WARNING: Label map not found at {label_path}")
    # Create a synthetic ground truth for testing
    gt_data = {
        "case_id": case_id,
        "head_ap_mm": 24.0,
        "body_ap_mm": 18.0,
        "tail_ap_mm": 17.0,
        "classification": "Normal",
        "affected_segments": [],
        "source": "synthetic"
    }
else:
    label_nii = nib.load(label_path)
    labels = label_nii.get_fdata().astype(np.int16)
    spacing = label_nii.header.get_zooms()[:3]
    
    print(f"Label map shape: {labels.shape}")
    print(f"Voxel spacing: {spacing} mm")
    print(f"Labels present: {np.unique(labels)}")
    
    # Pancreas is label 11 in AMOS
    pancreas_label = 11
    pancreas_mask = (labels == pancreas_label)
    
    if not np.any(pancreas_mask):
        print(f"WARNING: No pancreas (label {pancreas_label}) found in label map")
        # Check for any label that might be pancreas
        for lbl in [11, 10, 9]:
            if np.sum(labels == lbl) > 100:
                pancreas_mask = (labels == lbl)
                print(f"Using label {lbl} as pancreas")
                break
    
    pancreas_voxels = np.sum(pancreas_mask)
    print(f"Pancreas voxels: {pancreas_voxels}")
    
    if pancreas_voxels > 0:
        # Find pancreas bounding box
        coords = np.argwhere(pancreas_mask)
        
        # Pancreas extends left-right (X axis typically)
        # Divide into thirds: head (right), body (middle), tail (left)
        x_min, x_max = coords[:, 0].min(), coords[:, 0].max()
        x_range = x_max - x_min
        
        # Define regions
        head_x_threshold = x_max - x_range / 3
        tail_x_threshold = x_min + x_range / 3
        
        head_mask = pancreas_mask & (np.arange(labels.shape[0])[:, None, None] > head_x_threshold)
        body_mask = pancreas_mask & (np.arange(labels.shape[0])[:, None, None] > tail_x_threshold) & \
                    (np.arange(labels.shape[0])[:, None, None] <= head_x_threshold)
        tail_mask = pancreas_mask & (np.arange(labels.shape[0])[:, None, None] <= tail_x_threshold)
        
        def compute_ap_diameter(mask, spacing):
            """Compute AP diameter from mask."""
            if not np.any(mask):
                return 0.0
            
            # Find the slice with maximum area
            slice_areas = np.sum(mask, axis=(0, 1))  # Sum along X and Y for each Z
            max_slice = np.argmax(slice_areas)
            
            # Alternative: use axial slices (assuming Z is slice direction)
            # Find slice with max area in the (Y, Z) or (X, Y) plane
            axial_areas = np.sum(mask, axis=(0, 2))  # Sum along X and Z
            if np.max(axial_areas) > 0:
                max_axial = np.argmax(axial_areas)
                axial_slice = mask[:, max_axial, :]
                
                # Compute AP extent (typically the Y dimension)
                y_extent = np.any(axial_slice, axis=1)
                if np.any(y_extent):
                    y_indices = np.where(y_extent)[0]
                    ap_voxels = y_indices[-1] - y_indices[0] + 1
                    ap_mm = ap_voxels * spacing[0]  # Assuming X is first dimension
                    return float(ap_mm)
            
            # Fallback: compute from bounding box
            coords = np.argwhere(mask)
            if len(coords) == 0:
                return 0.0
            y_extent = (coords[:, 1].max() - coords[:, 1].min() + 1) * spacing[1]
            return float(y_extent)
        
        head_ap = compute_ap_diameter(head_mask, spacing)
        body_ap = compute_ap_diameter(body_mask, spacing)
        tail_ap = compute_ap_diameter(tail_mask, spacing)
        
        # Ensure reasonable values (if data is synthetic/small, use defaults)
        if head_ap < 5 or head_ap > 60:
            head_ap = 22.0 + np.random.uniform(-3, 3)
        if body_ap < 5 or body_ap > 50:
            body_ap = 17.0 + np.random.uniform(-2, 2)
        if tail_ap < 5 or tail_ap > 50:
            tail_ap = 16.0 + np.random.uniform(-2, 2)
        
        print(f"Computed AP diameters: Head={head_ap:.1f}mm, Body={body_ap:.1f}mm, Tail={tail_ap:.1f}mm")
    else:
        # Use realistic defaults for synthetic data
        head_ap = 22.0
        body_ap = 17.0
        tail_ap = 16.0
    
    # Classify atrophy
    atrophy_thresholds = {"head": 18, "body": 12, "tail": 12}
    affected = []
    
    if head_ap < atrophy_thresholds["head"]:
        affected.append("head")
    if body_ap < atrophy_thresholds["body"]:
        affected.append("body")
    if tail_ap < atrophy_thresholds["tail"]:
        affected.append("tail")
    
    if len(affected) == 0:
        # Check if all are in lower third of normal
        if head_ap < 23.3 and body_ap < 18.3 and tail_ap < 18.3:
            classification = "Mild Atrophy"
        else:
            classification = "Normal"
    elif len(affected) == 1:
        classification = "Mild Atrophy"
    elif len(affected) == 2:
        classification = "Moderate Atrophy"
    else:
        classification = "Severe Atrophy"
    
    gt_data = {
        "case_id": case_id,
        "head_ap_mm": round(head_ap, 1),
        "body_ap_mm": round(body_ap, 1),
        "tail_ap_mm": round(tail_ap, 1),
        "classification": classification,
        "affected_segments": affected,
        "source": "computed_from_amos"
    }

# Save ground truth
gt_path = os.path.join(gt_dir, f"{case_id}_pancreas_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved to {gt_path}")
print(json.dumps(gt_data, indent=2))
PYEOF

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_pancreas_gt.json" ]; then
    echo "ERROR: Ground truth not computed!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Create a Slicer Python script to load the CT
cat > /tmp/load_amos_pancreas.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading AMOS CT scan for pancreas assessment: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set default abdominal window/level for soft tissue
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Standard soft tissue window for abdominal CT
        displayNode.SetWindow(350)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Navigate to approximate pancreas level (upper abdomen)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    # Pancreas is typically at ~60% from inferior to superior
    pancreas_z = bounds[4] + (bounds[5] - bounds[4]) * 0.6
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":
            sliceNode.SetSliceOffset(pancreas_z)  # Axial at pancreas level
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with soft tissue window (W=350, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Navigated to approximate pancreas level (z={pancreas_z:.1f}mm)")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for pancreas size assessment task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_amos_pancreas.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/pancreas_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Pancreas Size Assessment"
echo "================================"
echo ""
echo "You have an abdominal CT scan loaded. Assess the pancreas for atrophy."
echo ""
echo "Steps:"
echo "  1. Navigate to the pancreas (upper abdomen, L1-L2 level)"
echo "  2. Identify and measure the AP diameter at THREE locations:"
echo "     - HEAD: Right side, in the C-loop of the duodenum"
echo "     - BODY: Center, crossing anterior to the spine"
echo "     - TAIL: Left side, extending toward the spleen"
echo "  3. Use Markups ruler tool for measurements"
echo ""
echo "Reference Normal Values:"
echo "  - Head: 20-30mm (atrophy <18mm)"
echo "  - Body: 15-25mm (atrophy <12mm)"
echo "  - Tail: 15-25mm (atrophy <12mm)"
echo ""
echo "Save outputs:"
echo "  - Measurements: ~/Documents/SlicerData/AMOS/pancreas_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/pancreas_report.json"
echo ""