#!/bin/bash
echo "=== Setting up Scroll and Measure Aorta Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Prepare AMOS data
echo "Preparing AMOS data..."
export CASE_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
echo "Using case: $CASE_ID"

if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT not found at $CT_FILE"
    exit 1
fi

# Record initial state
rm -f /tmp/scroll_aorta_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/aorta_diameter.mrk.json" 2>/dev/null || true
echo "$(date -Iseconds)" > /tmp/task_start_time

# Create Python script to load CT and position SLIGHTLY OFF from optimal aorta slice
cat > /tmp/setup_scroll_aorta.py << 'PYEOF'
import slicer
import os
import numpy as np

ct_path = os.environ.get('CT_FILE', '/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz')
case_id = os.environ.get('CASE_ID', 'amos_0001')

print(f"Loading AMOS CT: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")

    # Set abdominal window
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)

    # Set as background
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())

    # Find the aorta region (approximately middle of abdomen)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center_z = (bounds[4] + bounds[5]) / 2

    # Position 3 slices BELOW optimal (agent needs to scroll UP)
    spacing = volume_node.GetSpacing()
    offset_slices = 3
    offset_position = center_z - (offset_slices * spacing[2])

    # Set axial slice to this OFFSET position
    red_logic = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
    red_logic.SetSliceOffset(offset_position)

    # Save the positions for verification
    optimal_position = center_z
    with open('/tmp/scroll_aorta_positions.txt', 'w') as f:
        f.write(f"initial={offset_position:.2f}\n")
        f.write(f"optimal={optimal_position:.2f}\n")
        f.write(f"spacing={spacing[2]:.2f}\n")

    slicer.util.resetSliceViews()

    print(f"CT loaded")
    print(f"Initial slice: {offset_position:.1f}mm")
    print(f"Optimal slice: {optimal_position:.1f}mm")
    print(f"Agent should scroll UP ~{offset_slices} slices")

# Navigate to Markups
slicer.util.selectModule("Markups")

print("Setup complete - aorta visible but not optimally centered")
PYEOF

# Kill existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

export CT_FILE="$CT_FILE"
export CASE_ID="$CASE_ID"

# Launch Slicer
echo "Launching 3D Slicer..."
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" CASE_ID="$CASE_ID" /opt/Slicer/Slicer --python-script /tmp/setup_scroll_aorta.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/scroll_aorta_initial.png ga

echo "=== Setup Complete ==="
