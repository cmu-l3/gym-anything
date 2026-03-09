#!/bin/bash
echo "=== Setting up Aortic Tapering Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Prepare AMOS data (creates synthetic CT with known aortic geometry)
echo "Preparing AMOS abdominal CT data..."
export CASE_ID AMOS_DIR GROUND_TRUTH_DIR
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
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "ERROR: Ground truth not found at $GT_FILE"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Record initial state - remove any previous outputs
rm -f /tmp/aortic_tapering_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/aortic_measurements.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/tapering_report.json" 2>/dev/null || true

# Create a Slicer Python script to load the CT with optimal settings
cat > /tmp/load_aortic_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT scan: {case_id}...")

# Load the volume
volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set optimal window/level for vascular assessment
    # Contrast-enhanced aorta viewing: wider window to see vessel walls
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(500)  # Wide window for vessels
        displayNode.SetLevel(100)   # Centered on contrast
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background volume in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset slice views
    slicer.util.resetSliceViews()
    
    # Get volume bounds and center on data
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Calculate center
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    # Set slice positions to center of volume
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        if color == "Red":      # Axial view - most important for aorta measurement
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:                   # Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    # Switch to conventional layout (axial primary)
    layoutManager = slicer.app.layoutManager()
    layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
    
    print(f"CT loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Window/Level set for vascular assessment (W=500, L=100)")
    print(f"")
    print(f"The aorta should be visible as a bright circular structure")
    print(f"anterior to the spine in the axial (Red) view.")
    print(f"")
    print(f"Use the scroll wheel in the Red slice view to navigate")
    print(f"through the abdominal aorta from superior to inferior.")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for aortic tapering assessment")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_aortic_ct.py > /tmp/slicer_launch.log 2>&1 &

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
echo "Capturing initial state screenshot..."
take_screenshot /tmp/aortic_initial.png ga

# Verify screenshot was captured
if [ -f /tmp/aortic_initial.png ]; then
    SIZE=$(stat -c %s /tmp/aortic_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Aortic Tapering Assessment"
echo "================================="
echo ""
echo "Measurement Protocol:"
echo "  1. SUPRARENAL level (above renal arteries, ~L1-L2): Measure diameter"
echo "  2. INFRARENAL level (below renal arteries, ~L2-L3): Measure diameter"
echo "  3. BIFURCATION level (just above iliac split, ~L4-L5): Measure diameter"
echo "  4. Identify any FOCAL DILATIONS while scrolling"
echo ""
echo "Required Outputs:"
echo "  - Measurements: ~/Documents/SlicerData/AMOS/aortic_measurements.mrk.json"
echo "  - Report JSON: ~/Documents/SlicerData/AMOS/tapering_report.json"
echo ""
echo "Tip: Use Markups > Line (ruler) tool to measure diameters"
echo "     Place measurement perpendicular to vessel, outer-to-outer wall"
echo ""