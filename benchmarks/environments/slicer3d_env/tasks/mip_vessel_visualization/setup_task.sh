#!/bin/bash
echo "=== Setting up MIP Vessel Visualization Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Prepare AMOS data (downloads real data or generates synthetic)
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

# Clean up any previous task artifacts
echo "Cleaning up previous artifacts..."
rm -f "$AMOS_DIR/aorta_mip.png" 2>/dev/null || true
rm -f "$AMOS_DIR/mip_parameters.json" 2>/dev/null || true
rm -f /tmp/mip_task_result.json 2>/dev/null || true

# Ensure output directory exists with proper permissions
mkdir -p "$AMOS_DIR"
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chmod -R 755 "$AMOS_DIR" 2>/dev/null || true

# Create a Slicer Python script to load the CT with appropriate settings
cat > /tmp/load_amos_for_mip.py << 'PYEOF'
import slicer
import os

ct_path = os.environ.get("CT_FILE", "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz")
case_id = os.environ.get("CASE_ID", "amos_0001")

print(f"Loading CT scan for MIP visualization: {case_id}...")

# Load the volume
volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set initial display settings for CT viewing
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Standard abdominal CT window/level
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset slice views
    slicer.util.resetSliceViews()
    
    # Center on the data
    bounds = [0] * 6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT volume loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Initial window/level: W=400, L=40")
else:
    print("ERROR: Could not load CT volume")

print("")
print("Task: Create a Maximum Intensity Projection (MIP) visualization")
print("Use Volume Rendering module to create MIP of the aorta")
PYEOF

# Export environment variables for the Python script
export CT_FILE CASE_ID

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" CASE_ID="$CASE_ID" /opt/Slicer/Slicer --python-script /tmp/load_amos_for_mip.py > /tmp/slicer_launch.log 2>&1 &

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
echo "Capturing initial state..."
take_screenshot /tmp/mip_initial.png ga

# Verify screenshot was captured
if [ -f /tmp/mip_initial.png ]; then
    SIZE=$(stat -c %s /tmp/mip_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Maximum Intensity Projection (MIP) Vessel Visualization"
echo "=============================================================="
echo ""
echo "You have an abdominal CT scan loaded. Create a diagnostic-quality"
echo "MIP visualization of the abdominal aorta."
echo ""
echo "Steps:"
echo "  1. Go to Volume Rendering module"
echo "  2. Enable volume rendering for AbdominalCT"
echo "  3. Select MIP rendering preset or configure for vessels"
echo "  4. Set slab thickness: 100-150mm"
echo "  5. Adjust window/level: W=400-600, L=150-250"
echo "  6. Rotate to coronal (AP) view showing aorta vertically"
echo "  7. Capture screenshot of the MIP"
echo ""
echo "Save outputs:"
echo "  - MIP image: ~/Documents/SlicerData/AMOS/aorta_mip.png"
echo "  - Parameters: ~/Documents/SlicerData/AMOS/mip_parameters.json"
echo ""