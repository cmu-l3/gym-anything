#!/bin/bash
echo "=== Setting up Lumbar Lordosis Angle Measurement Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Prepare AMOS data with spine (downloads/generates data if not exists)
echo "Preparing AMOS data with lumbar spine..."
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

# Generate ground truth for lumbar lordosis measurement
echo "Generating lumbar lordosis ground truth..."
python3 << 'PYEOF'
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

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")

# Load CT to get dimensions and spacing
img = nib.load(ct_path)
data = img.get_fdata()
spacing = img.header.get_zooms()[:3]
shape = data.shape

print(f"CT shape: {shape}, spacing: {spacing}")

# Calculate spine geometry for ground truth
# In our synthetic data, spine is positioned at center_y + 50
nx, ny, nz = shape
center_x, center_y = nx // 2, ny // 2

# The lumbar spine spans roughly from L1 to S1
# In abdominal CT, this is typically in the mid-to-lower portion of the scan
# Total z coverage: nz * spacing[2] mm

total_z_mm = nz * spacing[2]
print(f"Total z coverage: {total_z_mm:.1f} mm")

# Simulate lordosis angle based on typical human anatomy
# Normal lumbar lordosis is 40-60 degrees
# We'll set a specific ground truth angle for verification
np.random.seed(42)

# L1 is typically at ~40% of abdominal scan height from top
# S1 is typically at ~85% of abdominal scan height from top
l1_z_fraction = 0.40
s1_z_fraction = 0.85

l1_slice = int(nz * l1_z_fraction)
s1_slice = int(nz * s1_z_fraction)

l1_z_mm = l1_slice * spacing[2]
s1_z_mm = s1_slice * spacing[2]

# Calculate the ground truth lordosis angle
# In a normal spine, L1 superior endplate tilts forward ~5-10 degrees
# S1 superior endplate tilts forward ~30-40 degrees
# The lordosis angle is the angle between perpendiculars to these lines

# For synthetic ground truth, we'll use a specific angle
# Normal lordosis: ~48 degrees (middle of normal range)
gt_lordosis_angle = 48.0  # degrees

# Simulate the vertebral positions for L1 and S1
# Spine is posterior (higher y in our coordinate system)
spine_y = center_y + 50  # From our synthetic data generation

# L1 position (at l1_z_mm height)
l1_position = {
    "slice_index": l1_slice,
    "z_mm": float(l1_z_mm),
    "center_x_mm": float(center_x * spacing[0]),
    "center_y_mm": float(spine_y * spacing[1]),
    "vertebral_level": "L1"
}

# S1 position (at s1_z_mm height)  
s1_position = {
    "slice_index": s1_slice,
    "z_mm": float(s1_z_mm),
    "center_x_mm": float(center_x * spacing[0]),
    "center_y_mm": float((spine_y + 5) * spacing[1]),  # Slightly more posterior
    "vertebral_level": "S1"
}

# Determine clinical classification
if gt_lordosis_angle < 30:
    classification = "Hypolordosis"
elif gt_lordosis_angle < 40:
    classification = "Low-normal"
elif gt_lordosis_angle <= 60:
    classification = "Normal"
elif gt_lordosis_angle <= 70:
    classification = "High-normal"
else:
    classification = "Hyperlordosis"

# Create ground truth JSON
ground_truth = {
    "case_id": case_id,
    "lumbar_lordosis_angle_degrees": gt_lordosis_angle,
    "classification": classification,
    "l1_position": l1_position,
    "s1_position": s1_position,
    "measurement_method": "Cobb",
    "voxel_spacing_mm": [float(s) for s in spacing],
    "volume_dimensions": list(shape),
    "total_z_coverage_mm": float(total_z_mm),
    "acceptable_angle_error_degrees": 8.0,
    "acceptable_z_error_mm": 25.0
}

# Save ground truth
gt_path = os.path.join(gt_dir, f"{case_id}_lordosis_gt.json")
os.makedirs(gt_dir, exist_ok=True)
with open(gt_path, "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"  Lordosis angle: {gt_lordosis_angle}°")
print(f"  Classification: {classification}")
print(f"  L1 at slice {l1_slice} (z={l1_z_mm:.1f}mm)")
print(f"  S1 at slice {s1_slice} (z={s1_z_mm:.1f}mm)")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_lordosis_gt.json" ]; then
    echo "ERROR: Ground truth not generated!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state
rm -f /tmp/lordosis_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/lumbar_lordosis_markups.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/lumbar_lordosis_report.json" 2>/dev/null || true
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso

# Create a Slicer Python script to load the CT with spine visualization
cat > /tmp/load_spine_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT for lumbar lordosis measurement: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("SpineCT")

    # Set bone window for spine visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Bone window settings for spine visualization
        displayNode.SetWindow(1500)
        displayNode.SetLevel(300)
        displayNode.SetAutoWindowLevel(False)

    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())

    # Set up sagittal view for spine measurement
    # Yellow slice is typically sagittal
    layoutManager = slicer.app.layoutManager()
    
    # Get volume bounds
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    # Set sagittal slice to midline (where spine is)
    yellowWidget = layoutManager.sliceWidget("Yellow")
    yellowLogic = yellowWidget.sliceLogic()
    yellowNode = yellowLogic.GetSliceNode()
    yellowNode.SetSliceOffset(center[0])  # Sagittal at midline
    
    # Set axial and coronal views
    redWidget = layoutManager.sliceWidget("Red")
    redLogic = redWidget.sliceLogic()
    redNode = redLogic.GetSliceNode()
    redNode.SetSliceOffset(center[2])  # Axial at middle height
    
    greenWidget = layoutManager.sliceWidget("Green")
    greenLogic = greenWidget.sliceLogic()
    greenNode = greenLogic.GetSliceNode()
    greenNode.SetSliceOffset(center[1])  # Coronal at spine level

    slicer.util.resetSliceViews()

    print(f"CT loaded with bone window (W=1500, L=300)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Sagittal view centered for spine visualization")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for lumbar lordosis measurement task")
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
take_screenshot /tmp/lordosis_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Lumbar Lordosis Angle Measurement"
echo "========================================"
echo ""
echo "You are given an abdominal CT scan with the lumbar spine visible."
echo "A spine surgeon needs the lumbar lordosis angle for surgical planning."
echo ""
echo "Your goal:"
echo "  1. Navigate to a sagittal (side) view of the lumbar spine"
echo "  2. Identify L1 (first lumbar vertebra, below T12 with lowest rib)"
echo "  3. Identify S1 (first sacral segment at sacral promontory)"
echo "  4. Place a line along the superior endplate of L1"
echo "  5. Place a line along the superior endplate of S1"
echo "  6. Measure the angle between these lines (lordosis angle)"
echo "  7. Classify the lordosis:"
echo "     - Hypolordosis (flat back): < 30°"
echo "     - Low-normal: 30-39°"
echo "     - Normal: 40-60°"
echo "     - High-normal: 61-70°"
echo "     - Hyperlordosis: > 70°"
echo ""
echo "Save your outputs:"
echo "  - Markups: ~/Documents/SlicerData/AMOS/lumbar_lordosis_markups.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/lumbar_lordosis_report.json"
echo ""
echo "The report should contain:"
echo "  - angle_degrees: measured angle"
echo "  - l1_identified: true/false"
echo "  - s1_identified: true/false"
echo "  - classification: clinical category"
echo "  - measurement_method: 'Cobb'"
echo ""