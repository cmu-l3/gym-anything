#!/bin/bash
echo "=== Setting up Ventricular Assessment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
GT_DIR="/var/lib/slicer/ground_truth"

# Ensure sample data directory exists
mkdir -p "$SAMPLE_DIR"
mkdir -p "$SAMPLE_DIR/Screenshots"
mkdir -p "$GT_DIR"
chmod 700 "$GT_DIR"

# Check if MRHead sample data exists
if [ ! -f "$SAMPLE_DIR/MRHead.nrrd" ]; then
    echo "MRHead sample data not found, attempting to download..."
    
    # Try multiple sources
    MRHEAD_DOWNLOADED=false
    
    # Try GitHub releases first
    if curl -L -o "$SAMPLE_DIR/MRHead.nrrd" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null; then
        if [ -f "$SAMPLE_DIR/MRHead.nrrd" ] && [ $(stat -c%s "$SAMPLE_DIR/MRHead.nrrd" 2>/dev/null || echo 0) -gt 1000000 ]; then
            echo "Downloaded MRHead.nrrd successfully"
            MRHEAD_DOWNLOADED=true
        fi
    fi
    
    # Try alternative URL
    if [ "$MRHEAD_DOWNLOADED" = "false" ]; then
        echo "Trying alternative URL..."
        if curl -L -o "$SAMPLE_DIR/MRHead.nrrd" --connect-timeout 30 --max-time 120 \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null; then
            if [ -f "$SAMPLE_DIR/MRHead.nrrd" ] && [ $(stat -c%s "$SAMPLE_DIR/MRHead.nrrd" 2>/dev/null || echo 0) -gt 1000000 ]; then
                echo "Downloaded MRHead.nrrd successfully"
                MRHEAD_DOWNLOADED=true
            fi
        fi
    fi
    
    if [ "$MRHEAD_DOWNLOADED" = "false" ]; then
        echo "ERROR: Could not download MRHead sample data"
        exit 1
    fi
fi

# Verify MRHead exists
if [ ! -f "$SAMPLE_DIR/MRHead.nrrd" ]; then
    echo "ERROR: MRHead.nrrd not found at $SAMPLE_DIR/MRHead.nrrd"
    exit 1
fi

echo "MRHead sample data verified: $(du -h "$SAMPLE_DIR/MRHead.nrrd" | cut -f1)"

# Generate ground truth reference values
cat > "$GT_DIR/mrhead_ventricle_gt.json" << 'GTEOF'
{
    "dataset": "MRHead",
    "description": "Ground truth reference for ventricular assessment",
    "expected_ranges": {
        "ventricular_volume_ml": {"min": 5, "max": 100, "typical_healthy": 15},
        "frontal_horn_width_mm": {"min": 15, "max": 60, "typical_healthy": 30},
        "internal_skull_diameter_mm": {"min": 100, "max": 180, "typical": 140},
        "evans_index": {"min": 0.15, "max": 0.50, "threshold_abnormal": 0.30}
    },
    "classification_thresholds": {
        "normal": {"volume_max": 20, "evans_max": 0.30},
        "mild": {"volume_max": 40, "evans_max": 0.33},
        "moderate": {"volume_max": 60, "evans_max": 0.37},
        "severe": {"volume_min": 60, "evans_min": 0.37}
    },
    "anatomical_notes": {
        "ventricle_location": "lateral_ventricles_bilateral",
        "measurement_level": "frontal_horns_axial",
        "csf_appearance": "dark_on_t1_weighted"
    }
}
GTEOF

chmod 600 "$GT_DIR/mrhead_ventricle_gt.json"

# Clean up any previous task artifacts
echo "Cleaning up previous task artifacts..."
rm -f "$SAMPLE_DIR/ventricle_segmentation.nii.gz" 2>/dev/null || true
rm -f "$SAMPLE_DIR/ventricle_segmentation.nii" 2>/dev/null || true
rm -f "$SAMPLE_DIR/frontal_horn_ruler.mrk.json" 2>/dev/null || true
rm -f "$SAMPLE_DIR/skull_diameter_ruler.mrk.json" 2>/dev/null || true
rm -f "$SAMPLE_DIR/ventricle_report.json" 2>/dev/null || true
rm -f /tmp/ventricle_task_result.json 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "mrhead_exists": true,
    "mrhead_size_bytes": $(stat -c%s "$SAMPLE_DIR/MRHead.nrrd" 2>/dev/null || echo 0),
    "segmentation_exists": false,
    "frontal_ruler_exists": false,
    "skull_ruler_exists": false,
    "report_exists": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create a Slicer Python script to load MRHead with optimal settings
cat > /tmp/load_mrhead_ventricle.py << 'PYEOF'
import slicer
import os

sample_dir = "/home/ga/Documents/SlicerData/SampleData"
mrhead_path = os.path.join(sample_dir, "MRHead.nrrd")

print("Loading MRHead brain MRI for ventricular assessment...")

# Load the volume
volume_node = slicer.util.loadVolume(mrhead_path)

if volume_node:
    volume_node.SetName("BrainMRI")
    print(f"Volume loaded: {volume_node.GetName()}")
    print(f"Dimensions: {volume_node.GetImageData().GetDimensions()}")
    
    # Get spacing for volume calculations
    spacing = volume_node.GetSpacing()
    print(f"Voxel spacing: {spacing} mm")
    
    # Set appropriate window/level for brain MRI (to see ventricles clearly)
    # Ventricles appear dark (CSF) on T1-weighted images
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Standard brain window for T1
        displayNode.SetWindow(600)
        displayNode.SetLevel(300)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Navigate to a slice that shows ventricles well (approximately mid-brain)
    bounds = [0] * 6
    volume_node.GetBounds(bounds)
    
    # Calculate center positions
    center_x = (bounds[0] + bounds[1]) / 2
    center_y = (bounds[2] + bounds[3]) / 2
    center_z = (bounds[4] + bounds[5]) / 2
    
    # Set slice positions - Red (axial) is key for Evans' index measurement
    layoutManager = slicer.app.layoutManager()
    
    # Red slice (axial) - center on brain
    redWidget = layoutManager.sliceWidget("Red")
    redLogic = redWidget.sliceLogic()
    redNode = redLogic.GetSliceNode()
    redNode.SetSliceOffset(center_z)
    
    # Green slice (coronal)
    greenWidget = layoutManager.sliceWidget("Green")
    greenLogic = greenWidget.sliceLogic()
    greenNode = greenLogic.GetSliceNode()
    greenNode.SetSliceOffset(center_y)
    
    # Yellow slice (sagittal)
    yellowWidget = layoutManager.sliceWidget("Yellow")
    yellowLogic = yellowWidget.sliceLogic()
    yellowNode = yellowLogic.GetSliceNode()
    yellowNode.SetSliceOffset(center_x)
    
    print(f"Views centered at: ({center_x:.1f}, {center_y:.1f}, {center_z:.1f})")
    print("Brain MRI loaded - ready for ventricular assessment")
    print("")
    print("TASK INSTRUCTIONS:")
    print("1. Segment the lateral ventricles using Segment Editor")
    print("2. Calculate volume using Segment Statistics")
    print("3. Measure Evans' Index with ruler markups on axial view")
    print("4. Create report with classification")
else:
    print("ERROR: Failed to load MRHead volume")

print("Setup complete")
PYEOF

# Launch Slicer with the loading script
echo "Launching 3D Slicer with brain MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_mrhead_ventricle.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to initialize..."
sleep 10

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for full initialization
sleep 10

# Maximize and focus Slicer window
SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
if [ -n "$SLICER_WID" ]; then
    echo "Found Slicer window: $SLICER_WID"
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
fi

# Wait for data to fully load
sleep 5

# Take initial state screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot "$SAMPLE_DIR/Screenshots/initial_state.png" 2>/dev/null || \
    DISPLAY=:1 import -window root "$SAMPLE_DIR/Screenshots/initial_state.png" 2>/dev/null || true

if [ -f "$SAMPLE_DIR/Screenshots/initial_state.png" ]; then
    SIZE=$(stat -c %s "$SAMPLE_DIR/Screenshots/initial_state.png" 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
    cp "$SAMPLE_DIR/Screenshots/initial_state.png" /tmp/task_initial.png 2>/dev/null || true
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Set permissions
chown -R ga:ga "$SAMPLE_DIR" 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Brain Ventricular Volume Assessment"
echo "=========================================="
echo ""
echo "A patient with memory complaints needs ventricular assessment."
echo ""
echo "Your goals:"
echo "  1. Segment the lateral ventricles (dark CSF spaces in brain)"
echo "  2. Calculate ventricular volume in mL"
echo "  3. Measure Evans' Index using ruler markups:"
echo "     - Frontal horn width / Internal skull diameter"
echo "  4. Classify: Normal, Mild, Moderate, or Severe enlargement"
echo ""
echo "Evans' Index thresholds:"
echo "  - Normal: < 0.30"
echo "  - Mild: 0.30-0.33"
echo "  - Moderate: 0.33-0.37"
echo "  - Severe/Hydrocephalus: > 0.37"
echo ""
echo "Save outputs to:"
echo "  ~/Documents/SlicerData/SampleData/ventricle_segmentation.nii.gz"
echo "  ~/Documents/SlicerData/SampleData/frontal_horn_ruler.mrk.json"
echo "  ~/Documents/SlicerData/SampleData/skull_diameter_ruler.mrk.json"
echo "  ~/Documents/SlicerData/SampleData/ventricle_report.json"
echo ""