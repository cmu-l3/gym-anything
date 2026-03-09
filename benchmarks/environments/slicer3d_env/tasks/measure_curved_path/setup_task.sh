#!/bin/bash
echo "=== Setting up Curved Path Measurement Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded"

# Prepare AMOS abdominal CT data
echo "Preparing AMOS abdominal CT data..."
/workspace/scripts/prepare_amos_data.sh "amos_0001"

# Get the case ID that was prepared
CASE_ID="amos_0001"
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
DATA_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

# Verify data exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: AMOS data not found at $DATA_FILE"
    exit 1
fi

echo "Data file: $DATA_FILE"
echo "Case ID: $CASE_ID"

# Record initial state - count existing curve files
INITIAL_CURVE_COUNT=$(find "$AMOS_DIR" -name "*.mrk.json" -type f 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_CURVE_COUNT" > /tmp/initial_curve_count.txt
echo "Initial curve file count: $INITIAL_CURVE_COUNT"

# Clean previous task outputs
rm -f "$AMOS_DIR/aorta_curve.mrk.json" 2>/dev/null || true
rm -f /tmp/curve_task_result.json 2>/dev/null || true

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Python script to load data and set up view
SETUP_SCRIPT="/tmp/setup_curve_task.py"
cat > "$SETUP_SCRIPT" << 'PYEOF'
import slicer
import os

# Load the CT volume
data_file = os.environ.get("DATA_FILE", "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz")
print(f"Loading CT volume: {data_file}")

try:
    # Load volume
    volumeNode = slicer.util.loadVolume(data_file)
    
    if volumeNode:
        print(f"Volume loaded: {volumeNode.GetName()}")
        
        # Set up appropriate window/level for contrast CT (soft tissue window)
        displayNode = volumeNode.GetDisplayNode()
        if displayNode:
            displayNode.SetAutoWindowLevel(False)
            displayNode.SetWindow(400)  # Soft tissue window width
            displayNode.SetLevel(50)    # Soft tissue window center
            print("Window/Level set to soft tissue preset (W:400, L:50)")
        
        # Get volume dimensions and navigate to mid-abdomen
        bounds = [0]*6
        volumeNode.GetRASBounds(bounds)
        
        # Navigate to middle of the volume (where aorta is typically visible)
        mid_axial = (bounds[4] + bounds[5]) / 2
        
        # Set slice offset to mid-abdomen
        layoutManager = slicer.app.layoutManager()
        red = layoutManager.sliceWidget("Red")
        if red:
            redLogic = red.sliceLogic()
            redLogic.SetSliceOffset(mid_axial)
            print(f"Navigated to axial slice at z={mid_axial:.1f}")
        
        # Switch to conventional layout (four-up with 3D)
        slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
        
        # Reset 3D view
        threeDWidget = layoutManager.threeDWidget(0)
        if threeDWidget:
            threeDWidget.threeDView().resetFocalPoint()
        
    else:
        print("ERROR: Failed to load volume")
        
except Exception as e:
    print(f"ERROR during setup: {e}")

# Clear any existing curve markups from previous attempts
curveNodes = slicer.mrmlScene.GetNodesByClass("vtkMRMLMarkupsCurveNode")
removed_count = 0
for i in range(curveNodes.GetNumberOfItems()):
    node = curveNodes.GetItemAsObject(i)
    if node:
        slicer.mrmlScene.RemoveNode(node)
        removed_count += 1
if removed_count > 0:
    print(f"Removed {removed_count} existing curve markup(s)")

print("Setup complete - ready for curve measurement task")
PYEOF

export DATA_FILE

# Launch Slicer with the setup script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script "$SETUP_SCRIPT" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in $(seq 1 90); do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer" | head -1 | awk '{print $1}')
        if [ -n "$SLICER_WID" ]; then
            echo "3D Slicer window detected after ${i}s"
            break
        fi
    fi
    sleep 1
done

# Wait extra time for data loading
echo "Waiting for data to load..."
sleep 15

# Focus and maximize Slicer window
SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer" | head -1 | awk '{print $1}')
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Slicer window focused and maximized"
else
    echo "WARNING: Could not find Slicer window"
fi

# Take initial screenshot
mkdir -p /home/ga/Documents/SlicerData/Screenshots
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot captured"

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Measure the curved path length of the abdominal aorta"
echo ""
echo "The aorta is visible as a bright circular structure in the center of the abdomen."
echo "Create a Curve markup (not a Line) and place control points along the aorta centerline"
echo "from the renal level to the iliac bifurcation."
echo ""
echo "Expected measurement: 80-160mm"
echo "Minimum control points: 8"
echo "Output file: ~/Documents/SlicerData/AMOS/aorta_curve.mrk.json"