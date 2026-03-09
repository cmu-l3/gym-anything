#!/bin/bash
echo "=== Setting up Intervertebral Disc Height Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Prepare AMOS data with spine structures
echo "Preparing AMOS CT data with spine structures..."
export CASE_ID GROUND_TRUTH_DIR AMOS_DIR

# Run the standard AMOS preparation first
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

# Generate disc height ground truth measurements
echo "Generating disc height ground truth..."
python3 << 'PYEOF'
import os
import json
import numpy as np

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
ct_img = nib.load(ct_path)
ct_data = ct_img.get_fdata()
spacing = ct_img.header.get_zooms()[:3]

print(f"CT shape: {ct_data.shape}, spacing: {spacing}")

# For L4-L5 disc measurements, we need to identify the spine region
# In the synthetic data, the spine is a cylinder at a known position
# For real data, we would need to analyze the CT for vertebral bodies

# Set ground truth values based on typical degenerated disc
# These will be our "expected" values for verification
np.random.seed(42)

# Simulate a mildly degenerated disc (common in older patients)
# Normal L4-L5: Anterior 12-14mm, Posterior 6-8mm
# Degenerated: Anterior 8-11mm, Posterior 4-6mm
anterior_height = 9.5 + np.random.uniform(-0.5, 0.5)  # mm
posterior_height = 5.2 + np.random.uniform(-0.3, 0.3)  # mm
vertebral_height = 28.0 + np.random.uniform(-1.0, 1.0)  # mm

mean_disc_height = (anterior_height + posterior_height) / 2
dhi = mean_disc_height / vertebral_height

# Classify
if dhi > 0.40:
    classification = "Normal"
elif dhi >= 0.30:
    classification = "Mild"
elif dhi >= 0.20:
    classification = "Moderate"
else:
    classification = "Severe"

# Calculate measurement positions in image coordinates
# Assuming midline sagittal plane
center_x = ct_data.shape[0] // 2
center_y = ct_data.shape[1] // 2

# L4-L5 disc is typically around 40-50% of the way up the abdomen
# For our 100-slice volume, this would be around slice 45-50
l4l5_slice = int(ct_data.shape[2] * 0.45)

# Spine is posterior (higher Y values in our synthetic data)
spine_y = center_y + int(50 / spacing[1])  # 50mm posterior to center

gt_data = {
    "case_id": case_id,
    "target_level": "L4-L5",
    "measurements": {
        "anterior_height_mm": float(round(anterior_height, 2)),
        "posterior_height_mm": float(round(posterior_height, 2)),
        "vertebral_height_mm": float(round(vertebral_height, 2)),
        "mean_disc_height_mm": float(round(mean_disc_height, 2)),
        "disc_height_index": float(round(dhi, 4))
    },
    "classification": classification,
    "measurement_region": {
        "approximate_slice_z": l4l5_slice,
        "spine_center_x": center_x,
        "spine_y": spine_y,
        "voxel_spacing_mm": [float(s) for s in spacing]
    },
    "tolerances": {
        "height_tolerance_mm": 2.0,
        "dhi_tolerance": 0.05,
        "level_tolerance": 1
    }
}

gt_path = os.path.join(gt_dir, f"{case_id}_disc_gt.json")
os.makedirs(gt_dir, exist_ok=True)
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"Expected measurements:")
print(f"  Anterior height: {anterior_height:.2f} mm")
print(f"  Posterior height: {posterior_height:.2f} mm")
print(f"  Vertebral height: {vertebral_height:.2f} mm")
print(f"  DHI: {dhi:.4f}")
print(f"  Classification: {classification}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_disc_gt.json" ]; then
    echo "ERROR: Failed to create disc ground truth!"
    exit 1
fi
echo "Ground truth verified"

# Clean any previous agent output
rm -f "$AMOS_DIR/disc_measurements.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/disc_report.json" 2>/dev/null || true
rm -f /tmp/disc_task_result.json 2>/dev/null || true

# Create a Slicer Python script to load the CT with bone window
cat > /tmp/load_spine_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading CT scan for spine assessment: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("SpineCT")
    
    # Set bone window for better vertebral visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Bone window: W=2000, L=400 (good for seeing vertebrae and discs)
        displayNode.SetWindow(2000)
        displayNode.SetLevel(400)
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
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    # Set up views - we want Yellow (sagittal) to be ready for disc measurement
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Yellow - Sagittal (key view for disc measurement)
            sliceNode.SetSliceOffset(center[0])
    
    # Switch to conventional layout with sagittal prominently visible
    layoutManager = slicer.app.layoutManager()
    layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
    
    print(f"CT loaded with bone window (W=2000, L=400)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Use sagittal view (yellow) for disc height measurements")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for disc height assessment task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with spine CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_spine_ct.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/disc_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Intervertebral Disc Height Assessment"
echo "============================================"
echo ""
echo "You are given an abdominal/lumbar CT scan. Evaluate the patient"
echo "for degenerative disc disease at the L4-L5 level."
echo ""
echo "Instructions:"
echo "  1. Navigate to the SAGITTAL view (yellow slice)"
echo "  2. Find the midline of the spine (spinous processes)"
echo "  3. Identify the L4-L5 disc (L5 is lowest lumbar vertebra)"
echo "  4. Use Markups ruler to measure:"
echo "     - Anterior disc height (front of disc)"
echo "     - Posterior disc height (back of disc)"
echo "     - L4 or L5 vertebral body height"
echo "  5. Calculate DHI = (Ant + Post) / 2 / Vertebral height"
echo "  6. Classify: Normal (>0.40), Mild (0.30-0.40),"
echo "              Moderate (0.20-0.30), Severe (<0.20)"
echo ""
echo "Save outputs to:"
echo "  - ~/Documents/SlicerData/AMOS/disc_measurements.mrk.json"
echo "  - ~/Documents/SlicerData/AMOS/disc_report.json"
echo ""