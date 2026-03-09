#!/bin/bash
echo "=== Setting up Measure Between Fiducials Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"

# Prepare BraTS data
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
echo "Using sample: $SAMPLE_ID"

if [ ! -f "$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz" ]; then
    echo "ERROR: FLAIR volume not found!"
    exit 1
fi

# Record initial state
rm -f /tmp/measure_fiducials_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/distance_measurement.mrk.json" 2>/dev/null || true
echo "$(date -Iseconds)" > /tmp/task_start_time

# Create Python script to load data and place two fiducials
cat > /tmp/setup_fiducial_measure.py << 'PYEOF'
import slicer
import os
import numpy as np

sample_dir = os.environ.get('SAMPLE_DIR', '/home/ga/Documents/SlicerData/BraTS/BraTS2021_00000')
sample_id = os.environ.get('SAMPLE_ID', 'BraTS2021_00000')

print(f"Loading FLAIR from {sample_dir}...")

# Load FLAIR volume
flair_path = os.path.join(sample_dir, f"{sample_id}_flair.nii.gz")
if os.path.exists(flair_path):
    flair_node = slicer.util.loadVolume(flair_path)
    flair_node.SetName("FLAIR")
else:
    print(f"ERROR: {flair_path} not found")
    exit(1)

# Set as background
for color in ["Red", "Green", "Yellow"]:
    sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
    sliceCompositeNode.SetBackgroundVolumeID(flair_node.GetID())

# Get volume bounds to place fiducials
bounds = [0]*6
flair_node.GetBounds(bounds)
center_x = (bounds[0] + bounds[1]) / 2
center_y = (bounds[2] + bounds[3]) / 2
center_z = (bounds[4] + bounds[5]) / 2

# Set axial slice to center
red_logic = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
red_logic.SetSliceOffset(center_z)

# Create two fiducial points on opposite sides of the brain
# Point_A: left side, Point_B: right side
offset_x = (bounds[1] - bounds[0]) / 4  # Quarter width

point_a = [center_x - offset_x, center_y, center_z]
point_b = [center_x + offset_x, center_y, center_z]

# Create fiducial markup node
fiducialNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLMarkupsFiducialNode", "Reference_Points")
fiducialNode.AddControlPoint(point_a, "Point_A")
fiducialNode.AddControlPoint(point_b, "Point_B")

# Set display properties to make them visible
displayNode = fiducialNode.GetDisplayNode()
if displayNode:
    displayNode.SetVisibility(True)
    displayNode.SetSelectedColor(1, 0, 0)  # Red for selected
    displayNode.SetGlyphScale(3.0)  # Larger points
    displayNode.SetTextScale(4.0)  # Larger labels

# Calculate expected distance
import math
expected_distance = math.sqrt(sum((a-b)**2 for a,b in zip(point_a, point_b)))
print(f"Point_A: {point_a}")
print(f"Point_B: {point_b}")
print(f"Expected distance: {expected_distance:.2f}mm")

# Save ground truth
with open('/tmp/fiducial_distance_gt.txt', 'w') as f:
    f.write(f"{expected_distance:.2f}\n")
    f.write(f"{point_a[0]:.2f},{point_a[1]:.2f},{point_a[2]:.2f}\n")
    f.write(f"{point_b[0]:.2f},{point_b[1]:.2f},{point_b[2]:.2f}\n")

slicer.util.resetSliceViews()

# Navigate to Markups module
slicer.util.selectModule("Markups")

print("Setup complete - two fiducials placed, ready for distance measurement")
PYEOF

# Kill existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

export SAMPLE_DIR="$SAMPLE_DIR"
export SAMPLE_ID="$SAMPLE_ID"

# Launch Slicer
echo "Launching 3D Slicer with pre-placed fiducials..."
sudo -u ga DISPLAY=:1 SAMPLE_DIR="$SAMPLE_DIR" SAMPLE_ID="$SAMPLE_ID" /opt/Slicer/Slicer --python-script /tmp/setup_fiducial_measure.py > /tmp/slicer_launch.log 2>&1 &

wait_for_slicer 120
sleep 10

# Configure window
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    focus_window "$WID"
fi

sleep 3
take_screenshot /tmp/fiducial_measure_initial.png ga

echo "=== Setup Complete ==="
