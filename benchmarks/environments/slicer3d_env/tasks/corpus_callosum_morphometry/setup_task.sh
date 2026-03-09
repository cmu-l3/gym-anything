#!/bin/bash
echo "=== Setting up Corpus Callosum Morphometry Task ==="

source /workspace/scripts/task_utils.sh

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
MRHEAD_FILE="$SAMPLE_DIR/MRHead.nrrd"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Create directories
mkdir -p "$SAMPLE_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clean up any previous task outputs
rm -f "$SAMPLE_DIR/cc_measurements.mrk.json" 2>/dev/null || true
rm -f "$SAMPLE_DIR/corpus_callosum_report.json" 2>/dev/null || true
rm -f /tmp/cc_task_result.json 2>/dev/null || true

# Verify MRHead sample data exists
if [ ! -f "$MRHEAD_FILE" ]; then
    echo "MRHead sample not found, attempting to download..."
    
    # Try multiple sources
    cd "$SAMPLE_DIR"
    
    # Try GitHub Slicer testing data
    curl -L -o MRHead.nrrd --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || true
    
    # Verify download
    if [ ! -f "$MRHEAD_FILE" ] || [ $(stat -c%s "$MRHEAD_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Primary download failed, trying alternative..."
        wget --timeout=120 -O MRHead.nrrd \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
fi

# Final verification
if [ ! -f "$MRHEAD_FILE" ]; then
    echo "ERROR: Could not obtain MRHead sample data"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$MRHEAD_FILE" 2>/dev/null || echo "0")
echo "MRHead file found: $MRHEAD_FILE ($FILE_SIZE bytes)"

# Create ground truth measurements for MRHead
# These are pre-computed reference values for the MRHead dataset
echo "Setting up ground truth measurements..."

cat > "$GROUND_TRUTH_DIR/mrhead_cc_ground_truth.json" << 'GTEOF'
{
    "dataset": "MRHead",
    "measurement_protocol": "Standard corpus callosum morphometry",
    "measurements": {
        "total_length_mm": 71.5,
        "genu_thickness_mm": 10.8,
        "body_thickness_mm": 6.5,
        "splenium_thickness_mm": 11.2
    },
    "mid_sagittal_slice_range": {
        "min": 125,
        "max": 135,
        "optimal": 130
    },
    "normal_ranges": {
        "total_length_mm": {"min": 65, "max": 85},
        "genu_thickness_mm": {"min": 8, "max": 15},
        "body_thickness_mm": {"min": 5, "max": 10},
        "splenium_thickness_mm": {"min": 8, "max": 15}
    },
    "expected_classification": "Normal",
    "notes": "MRHead is a healthy adult brain MRI with normal corpus callosum"
}
GTEOF

chmod 600 "$GROUND_TRUTH_DIR/mrhead_cc_ground_truth.json"
echo "Ground truth created (hidden from agent)"

# Create Slicer Python script to load MRHead and set up views
cat > /tmp/load_mrhead_for_cc.py << 'PYEOF'
import slicer
import os

mrhead_path = "/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"

print("Loading MRHead volume for corpus callosum assessment...")

# Load the volume
volume_node = slicer.util.loadVolume(mrhead_path)

if volume_node:
    volume_node.SetName("MRHead_Brain")
    print(f"Volume loaded: {volume_node.GetName()}")
    print(f"Dimensions: {volume_node.GetImageData().GetDimensions()}")
    
    # Set up display - brain window/level
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(400)
        displayNode.SetLevel(200)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Get volume bounds
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Center each view
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        # Calculate center
        if color == "Red":  # Axial
            center = (bounds[4] + bounds[5]) / 2
        elif color == "Green":  # Sagittal - this is where corpus callosum is seen
            center = (bounds[2] + bounds[3]) / 2  # Mid-sagittal
        else:  # Yellow - Coronal
            center = (bounds[0] + bounds[1]) / 2
        
        sliceNode.SetSliceOffset(center)
    
    # Try to set layout to show sagittal prominently
    layoutManager = slicer.app.layoutManager()
    # Use conventional layout which shows all three views
    layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
    
    print("Views configured - use Green (Sagittal) slice for corpus callosum measurement")
    print("Navigate to mid-sagittal slice to see corpus callosum")
else:
    print("ERROR: Could not load MRHead volume")

print("Setup complete - ready for corpus callosum morphometry task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with MRHead
echo "Launching 3D Slicer with MRHead brain MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_mrhead_for_cc.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 90
sleep 8

# Configure window
echo "Configuring Slicer window..."
sleep 2

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to load
sleep 3

# Take initial screenshot
take_screenshot /tmp/cc_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Corpus Callosum Morphometry Assessment"
echo "============================================="
echo ""
echo "You have a T1-weighted brain MRI (MRHead) loaded."
echo ""
echo "Your goal:"
echo "  1. Navigate to the mid-sagittal slice (Green/Sagittal view)"
echo "     - The corpus callosum appears as a bright curved structure"
echo "  2. Measure the corpus callosum at standardized points:"
echo "     - Total LENGTH (genu to splenium)"
echo "     - GENU thickness (anterior bulb)"
echo "     - BODY thickness (middle section)"
echo "     - SPLENIUM thickness (posterior bulb)"
echo "  3. Assess atrophy grade based on measurements"
echo "  4. Save your outputs:"
echo "     - Markups: ~/Documents/SlicerData/SampleData/cc_measurements.mrk.json"
echo "     - Report: ~/Documents/SlicerData/SampleData/corpus_callosum_report.json"
echo ""
echo "Atrophy criteria:"
echo "  - Normal: length > 65mm AND all thickness > 5mm"
echo "  - Mild: length 55-65mm OR any thickness 4-5mm"
echo "  - Moderate-severe: length < 55mm OR any thickness < 4mm"
echo ""