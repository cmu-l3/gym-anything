#!/bin/bash
echo "=== Setting up Neural Foramen Stenosis Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time

# Prepare AMOS data (downloads real data or generates synthetic with spine)
echo "Preparing AMOS abdominal CT data..."
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

# Generate neural foramen ground truth measurements
echo "Generating neural foramen ground truth..."
python3 << 'PYEOF'
import os
import json
import numpy as np

case_id = os.environ.get("CASE_ID", "amos_0001")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
amos_dir = "/home/ga/Documents/SlicerData/AMOS"

try:
    import nibabel as nib
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

np.random.seed(42)

# Load CT to get spacing
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
ct = nib.load(ct_path)
spacing = ct.header.get_zooms()[:3]
shape = ct.shape

print(f"CT shape: {shape}, spacing: {spacing}")

# For synthetic data or real AMOS data, generate realistic neural foramen measurements
# These are based on typical anatomical values

# Normal lumbar foraminal dimensions (literature values):
# - Height: 18-23mm at L4-L5, 12-19mm at L5-S1
# - Width: 7-12mm
# L5-S1 is typically smaller due to normal anatomy

# Generate measurements with some asymmetry (realistic)
foramen_gt = {
    "L4L5_left": {
        "height_mm": float(np.random.uniform(16, 22)),
        "width_mm": float(np.random.uniform(7, 10)),
        "grade": 0  # Normal
    },
    "L4L5_right": {
        "height_mm": float(np.random.uniform(15, 21)),
        "width_mm": float(np.random.uniform(7, 10)),
        "grade": 0  # Normal
    },
    "L5S1_left": {
        "height_mm": float(np.random.uniform(12, 17)),
        "width_mm": float(np.random.uniform(6, 9)),
        "grade": 0  # Normal (on lower end but still normal)
    },
    "L5S1_right": {
        # Introduce mild stenosis on one side for clinical interest
        "height_mm": float(np.random.uniform(10, 14)),
        "width_mm": float(np.random.uniform(5, 7)),
        "grade": 1  # Mild stenosis
    }
}

# Calculate areas
for key in foramen_gt:
    h = foramen_gt[key]["height_mm"]
    w = foramen_gt[key]["width_mm"]
    foramen_gt[key]["area_mm2"] = float(h * w * 0.785)  # Elliptical approximation

    # Verify grading based on height
    if h >= 15:
        foramen_gt[key]["grade"] = 0
    elif h >= 10:
        foramen_gt[key]["grade"] = 1
    elif h >= 5:
        foramen_gt[key]["grade"] = 2
    else:
        foramen_gt[key]["grade"] = 3

# Add anatomical reference information
foramen_gt["reference_info"] = {
    "ct_spacing_mm": [float(s) for s in spacing],
    "ct_shape": [int(d) for d in shape],
    "l4l5_slice_range_approx": [int(shape[2] * 0.35), int(shape[2] * 0.45)],
    "l5s1_slice_range_approx": [int(shape[2] * 0.25), int(shape[2] * 0.35)],
    "measurement_plane": "sagittal",
    "grading_scale": {
        "0": "Normal (height >= 15mm)",
        "1": "Mild (height 10-15mm)",
        "2": "Moderate (height 5-10mm)",
        "3": "Severe (height < 5mm)"
    }
}

# Expected clinical impression based on findings
grades = [foramen_gt[k]["grade"] for k in ["L4L5_left", "L4L5_right", "L5S1_left", "L5S1_right"]]
max_grade = max(grades)
if max_grade == 0:
    foramen_gt["expected_impression"] = "No significant neural foraminal stenosis"
elif max_grade == 1:
    foramen_gt["expected_impression"] = "Mild neural foraminal narrowing"
elif max_grade == 2:
    foramen_gt["expected_impression"] = "Moderate neural foraminal stenosis"
else:
    foramen_gt["expected_impression"] = "Severe neural foraminal stenosis"

# Save ground truth
os.makedirs(gt_dir, exist_ok=True)
gt_path = os.path.join(gt_dir, f"{case_id}_foramen_gt.json")
with open(gt_path, "w") as f:
    json.dump(foramen_gt, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print("\nGround truth foramen measurements:")
for key in ["L4L5_left", "L4L5_right", "L5S1_left", "L5S1_right"]:
    m = foramen_gt[key]
    print(f"  {key}: H={m['height_mm']:.1f}mm, W={m['width_mm']:.1f}mm, Grade={m['grade']}")
print(f"Expected impression: {foramen_gt['expected_impression']}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_foramen_gt.json" ]; then
    echo "WARNING: Could not create ground truth file"
fi

# Clean up any previous outputs
rm -f "$AMOS_DIR/foramen_measurements.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/foramen_report.json" 2>/dev/null || true

# Create a Slicer Python script to load the CT and set up for spine viewing
cat > /tmp/load_foramen_ct.py << 'PYEOF'
import slicer
import os

ct_path = os.environ.get("CT_FILE", "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz")
case_id = os.environ.get("CASE_ID", "amos_0001")

print(f"Loading CT for neural foramen assessment: {case_id}")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("LumbarCT")
    
    # Set bone window for spine visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Bone window for spine assessment
        displayNode.SetWindow(2000)
        displayNode.SetLevel(400)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Get volume bounds to position at lumbar region
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Position slices - aim for lower third of volume (lumbar region)
    z_lumbar = bounds[4] + (bounds[5] - bounds[4]) * 0.35  # Lower third
    y_center = (bounds[2] + bounds[3]) / 2
    x_center = (bounds[0] + bounds[1]) / 2
    
    # Set slice positions
    slicer.app.layoutManager().sliceWidget("Red").sliceLogic().GetSliceNode().SetSliceOffset(z_lumbar)
    slicer.app.layoutManager().sliceWidget("Green").sliceLogic().GetSliceNode().SetSliceOffset(y_center)
    slicer.app.layoutManager().sliceWidget("Yellow").sliceLogic().GetSliceNode().SetSliceOffset(x_center)
    
    print(f"CT loaded with bone window (W=2000, L=400)")
    print(f"Positioned at lumbar region (z={z_lumbar:.1f}mm)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Spacing: {volume_node.GetSpacing()}")
else:
    print("WARNING: Could not load CT volume")

print("\n=== TASK: Neural Foramen Stenosis Assessment ===")
print("Use sagittal view to visualize and measure neural foramina")
print("Measure L4-L5 and L5-S1 foramina bilaterally")
PYEOF

# Set environment variables for the script
export CT_FILE CASE_ID

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with lumbar CT..."
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" CASE_ID="$CASE_ID" /opt/Slicer/Slicer --python-script /tmp/load_foramen_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window for optimal viewing
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
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/foramen_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Neural Foramen Stenosis Assessment"
echo "========================================="
echo ""
echo "A patient presents with leg pain/numbness. Assess the lumbar"
echo "neural foramina for stenosis that could explain radiculopathy."
echo ""
echo "Your goal:"
echo "  1. Navigate to the lumbar spine (L4-L5 at iliac crest level)"
echo "  2. Use SAGITTAL view to visualize neural foramina"
echo "  3. For L4-L5 (left and right) measure:"
echo "     - Foraminal HEIGHT (superior-inferior)"
echo "     - Foraminal WIDTH (anterior-posterior at narrowest)"
echo "  4. Repeat for L5-S1 bilaterally"
echo "  5. Grade each foramen:"
echo "     - Grade 0: Normal (height >= 15mm)"
echo "     - Grade 1: Mild (height 10-15mm)"
echo "     - Grade 2: Moderate (height 5-10mm)"
echo "     - Grade 3: Severe (height < 5mm)"
echo ""
echo "Save outputs to:"
echo "  - Measurements: ~/Documents/SlicerData/AMOS/foramen_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/foramen_report.json"
echo ""