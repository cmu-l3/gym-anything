#!/bin/bash
echo "=== Setting up HU Tissue Characterization Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Prepare AMOS data (downloads real data if not exists, generates synthetic if download fails)
echo "Preparing AMOS 2022 data..."
export CASE_ID AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"
echo "$CASE_ID" > /tmp/hu_task_case_id.txt

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE ($(du -h "$CT_FILE" | cut -f1))"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" ]; then
    echo "WARNING: Ground truth JSON not found - may limit verification"
fi

# Clean up any previous outputs
echo "Cleaning previous outputs..."
rm -f /tmp/hu_task_result.json 2>/dev/null || true
rm -f "$AMOS_DIR/tissue_rois.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/hu_tissue_report.json" 2>/dev/null || true
rm -f "$AMOS_DIR"/*.mrk.json 2>/dev/null || true

# Record initial file state for anti-gaming
find "$AMOS_DIR" -name "*.json" -o -name "*.mrk.json" 2>/dev/null | sort > /tmp/initial_amos_files.txt

# Create a Slicer Python script to load the CT with proper window/level
cat > /tmp/load_ct_for_hu.py << 'PYEOF'
import slicer
import os
import json

ct_path = os.environ.get("CT_FILE", "/home/ga/Documents/SlicerData/AMOS/amos_0001.nii.gz")
case_id = os.environ.get("CASE_ID", "amos_0001")

print(f"Loading CT scan for HU characterization: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set abdominal soft tissue window/level for HU visualization
    # This is important for seeing tissue differences
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Wide window to see all tissue types (bone to fat)
        displayNode.SetWindow(500)  # Wide window
        displayNode.SetLevel(50)    # Centered on soft tissue
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Get volume center for initial positioning
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    # Position slices near center of volume
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])  # Axial
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])  # Coronal
        else:
            sliceNode.SetSliceOffset(center[0])  # Sagittal
    
    # Get image statistics for reference
    imageData = volume_node.GetImageData()
    if imageData:
        dims = imageData.GetDimensions()
        spacing = volume_node.GetSpacing()
        print(f"Volume dimensions: {dims}")
        print(f"Voxel spacing (mm): {spacing}")
        print(f"Window: 500, Level: 50 (soft tissue preset)")
    
    print("CT loaded successfully - ready for HU tissue characterization")
else:
    print("ERROR: Could not load CT volume")

# Switch to conventional layout (four-up view is good for this task)
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

print("Setup complete")
PYEOF

# Set environment variables for the Python script
export CT_FILE CASE_ID

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 CT_FILE="$CT_FILE" CASE_ID="$CASE_ID" /opt/Slicer/Slicer --python-script /tmp/load_ct_for_hu.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/hu_task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: HU Tissue Characterization"
echo "================================="
echo ""
echo "You are given an abdominal CT scan. Sample HU values from five"
echo "different tissue types to demonstrate tissue characterization skills."
echo ""
echo "Required tissues to measure:"
echo "  1. Subcutaneous fat (anterior abdominal wall)"
echo "  2. Skeletal muscle (psoas or paraspinal)"  
echo "  3. Liver parenchyma (right lobe, avoid vessels)"
echo "  4. Aortic blood pool (abdominal aorta lumen)"
echo "  5. Vertebral bone (vertebral body, cancellous)"
echo ""
echo "Expected HU ranges:"
echo "  - Fat: -150 to -30 HU"
echo "  - Muscle: 10 to 70 HU"
echo "  - Liver: 40 to 150 HU"
echo "  - Blood (contrast): 100 to 350 HU"
echo "  - Bone (cancellous): 100 to 500 HU"
echo ""
echo "Save your outputs:"
echo "  - ROIs: ~/Documents/SlicerData/AMOS/tissue_rois.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/hu_tissue_report.json"
echo ""