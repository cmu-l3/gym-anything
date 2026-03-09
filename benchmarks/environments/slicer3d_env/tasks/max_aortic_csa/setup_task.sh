#!/bin/bash
echo "=== Setting up Maximum Aortic CSA Measurement Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SCREENSHOTS_DIR="/home/ga/Documents/SlicerData/Screenshots"
CASE_ID="amos_0001"

# Prepare AMOS data (downloads real data or generates synthetic if unavailable)
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

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Clean up any previous task artifacts
rm -f /tmp/max_aorta_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/max_aorta_measurement.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/max_aorta_report.json" 2>/dev/null || true
rm -f "$SCREENSHOTS_DIR/max_aorta_screenshot.png" 2>/dev/null || true

# Create screenshots directory if needed
mkdir -p "$SCREENSHOTS_DIR"
chown -R ga:ga "$SCREENSHOTS_DIR" 2>/dev/null || true

# Compute and store ground truth maximum CSA for verification
echo "Computing ground truth maximum CSA..."
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
    print(f"WARNING: Labels file not found at {labels_path}")
    sys.exit(0)

# Load label map
labels_nii = nib.load(labels_path)
labels_data = labels_nii.get_fdata().astype(np.int32)
voxel_dims = labels_nii.header.get_zooms()[:3]

print(f"Label volume shape: {labels_data.shape}")
print(f"Voxel dimensions: {voxel_dims} mm")

# Aorta is label 10 in AMOS dataset
aorta_label = 10
aorta_mask = (labels_data == aorta_label)

if not np.any(aorta_mask):
    print("WARNING: No aorta voxels found in label map")
    sys.exit(0)

# Calculate CSA for each axial slice
max_csa = 0
max_slice_idx = 0
slice_z_mm = 0
csa_per_slice = []

for z in range(labels_data.shape[2]):
    slice_mask = aorta_mask[:, :, z]
    area_voxels = np.sum(slice_mask)
    
    if area_voxels > 0:
        # Convert to mm²
        area_mm2 = area_voxels * voxel_dims[0] * voxel_dims[1]
        csa_per_slice.append((z, area_mm2))
        
        if area_mm2 > max_csa:
            max_csa = area_mm2
            max_slice_idx = z
            slice_z_mm = z * voxel_dims[2]

# Calculate equivalent diameter
equiv_diameter = 2 * np.sqrt(max_csa / np.pi) if max_csa > 0 else 0

# Clinical classification
if equiv_diameter < 30:
    classification = "Normal"
elif equiv_diameter < 35:
    classification = "Ectatic"
else:
    classification = "Aneurysmal"

# Save ground truth for verification
gt_max_csa = {
    "max_csa_mm2": float(max_csa),
    "max_slice_index": int(max_slice_idx),
    "slice_z_mm": float(slice_z_mm),
    "equivalent_diameter_mm": float(equiv_diameter),
    "classification": classification,
    "voxel_dims_mm": [float(v) for v in voxel_dims],
    "total_aorta_voxels": int(np.sum(aorta_mask)),
    "slices_with_aorta": len(csa_per_slice)
}

gt_output_path = os.path.join(gt_dir, f"{case_id}_max_csa_gt.json")
with open(gt_output_path, "w") as f:
    json.dump(gt_max_csa, f, indent=2)

print(f"Ground truth max CSA: {max_csa:.1f} mm² at slice {max_slice_idx} (z={slice_z_mm:.1f}mm)")
print(f"Equivalent diameter: {equiv_diameter:.1f} mm ({classification})")
print(f"Ground truth saved to {gt_output_path}")
PYEOF

# Create a Slicer Python script to load the CT
cat > /tmp/load_amos_ct_csa.py << 'PYEOF'
import slicer
import os

ct_path = os.environ.get("CT_FILE", "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz")
case_id = os.environ.get("CASE_ID", "amos_0001")

print(f"Loading AMOS CT scan: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set default abdominal soft tissue window/level
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center the views on the data
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        # Calculate center
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        
        # Set slice offset based on view orientation
        if color == "Red":  # Axial - z
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal - y
            sliceNode.SetSliceOffset(center[1])
        else:  # Sagittal - x
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with abdominal window (W=400, L=50)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Spacing: {volume_node.GetSpacing()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for maximum CSA measurement task")
PYEOF

# Export environment variables for the Python script
export CT_FILE CASE_ID

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" CASE_ID="$CASE_ID" /opt/Slicer/Slicer --python-script /tmp/load_amos_ct_csa.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/max_aorta_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Maximum Aortic Cross-sectional Area Measurement"
echo "======================================================"
echo ""
echo "You are given an abdominal CT scan. The aorta may have variable"
echo "diameter along its length due to dilation."
echo ""
echo "Your goal:"
echo "  1. Navigate through the CT examining the abdominal aorta"
echo "     (large circular vessel anterior to the spine)"
echo "  2. Find the axial slice with the LARGEST aortic cross-section"
echo "  3. Measure the cross-sectional area (CSA) at that slice in mm²"
echo "  4. Record the z-coordinate (slice location)"
echo "  5. Calculate equivalent diameter: 2 × √(CSA / π)"
echo "  6. Classify: Normal (<30mm), Ectatic (30-35mm), Aneurysmal (>35mm)"
echo ""
echo "Save outputs:"
echo "  - Measurement: ~/Documents/SlicerData/AMOS/max_aorta_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/max_aorta_report.json"
echo "  - Screenshot: ~/Documents/SlicerData/Screenshots/max_aorta_screenshot.png"
echo ""