#!/bin/bash
echo "=== Setting up Surgical Anatomy Briefing Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 abdominal CT data..."
export CASE_ID GROUND_TRUTH_DIR AMOS_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
LABEL_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Verify ground truth labels exist (for verification only)
if [ ! -f "$LABEL_FILE" ]; then
    echo "ERROR: Ground truth labels not found at $LABEL_FILE"
    exit 1
fi
echo "Ground truth labels verified (hidden from agent)"

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt
echo "Task start time recorded"

# Clean up any previous output files
rm -f "$AMOS_DIR/anatomical_landmarks.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/briefing_axial.png" 2>/dev/null || true
rm -f "$AMOS_DIR/briefing_coronal.png" 2>/dev/null || true
rm -f "$AMOS_DIR/briefing_sagittal.png" 2>/dev/null || true
rm -f "$AMOS_DIR"/*.mrml 2>/dev/null || true
rm -f "$AMOS_DIR"/*.mrb 2>/dev/null || true
rm -f /tmp/anatomy_task_result.json 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "case_id": "$CASE_ID",
    "ct_file": "$CT_FILE",
    "output_dir": "$AMOS_DIR"
}
EOF

# Create Slicer Python script to load the CT with appropriate settings
cat > /tmp/load_anatomy_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading abdominal CT scan: {case_id}...")

# Load the volume
volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set soft tissue window/level for abdominal anatomy
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset all slice views
    slicer.util.resetSliceViews()
    
    # Get volume bounds and center the views
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
    
    # Set each slice to center of volume
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":    # Axial
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center[1])
        else:  # Yellow - Sagittal
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded successfully")
    print(f"  Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"  Window/Level: W=400, L=40 (soft tissue)")
    print(f"  Center: {center}")
else:
    print("ERROR: Could not load CT volume")

# Switch to conventional layout (four-up view good for annotation)
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)

print("")
print("Setup complete - ready for anatomical annotation task")
print("Use Markups module to create fiducials on anatomical structures")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_anatomy_ct.py > /tmp/slicer_launch.log 2>&1 &

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
take_screenshot /tmp/anatomy_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Multi-Structure Anatomical Annotation for Surgical Briefing"
echo "=================================================================="
echo ""
echo "You are preparing a pre-operative briefing for a surgical team."
echo "An abdominal CT scan is loaded. Your goal is to create annotated"
echo "documentation of key anatomical structures."
echo ""
echo "Steps:"
echo "  1. Open the Markups module"
echo "  2. Create fiducial points on 8 structures:"
echo "     - Liver, Spleen, Right Kidney, Left Kidney"
echo "     - Aorta, IVC, Pancreas, Portal Vein (or Gallbladder)"
echo "  3. Label each fiducial with the structure name"
echo "  4. Capture screenshots from axial, coronal, and sagittal views"
echo "  5. Save the markup list and scene"
echo ""
echo "Output locations:"
echo "  - Fiducials: ~/Documents/SlicerData/AMOS/anatomical_landmarks.mrk.json"
echo "  - Screenshots: ~/Documents/SlicerData/AMOS/briefing_*.png"
echo ""