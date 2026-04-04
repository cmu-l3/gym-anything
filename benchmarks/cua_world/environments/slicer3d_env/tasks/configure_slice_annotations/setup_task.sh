#!/bin/bash
echo "=== Setting up Configure Slice Annotations Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial display settings state
echo "Recording initial state..."
cat > /tmp/initial_annotation_state.json << 'EOF'
{
    "timestamp": "$(date -Iseconds)",
    "orientation_markers_enabled": false,
    "patient_info_visible": true,
    "date_info_visible": true,
    "settings_modified": false
}
EOF

# Ensure sample data exists
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found, attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try multiple download sources
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    wget -O "$SAMPLE_FILE" --timeout=120 \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || \
        echo "Warning: Could not download sample data"
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

if [ -f "$SAMPLE_FILE" ]; then
    echo "Sample file exists: $SAMPLE_FILE ($(du -h "$SAMPLE_FILE" | cut -f1))"
else
    echo "WARNING: Sample file not found at $SAMPLE_FILE"
fi

# Clean any previous task results
rm -f /tmp/slice_annotations_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with sample data
echo "Launching 3D Slicer with MRHead data..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 1
done

# Wait additional time for data to load and UI to stabilize
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Set default annotation settings (enable patient info to create the "problem")
# This uses Slicer's Python interface to set initial state
echo "Setting initial annotation state (with patient info visible)..."
cat > /tmp/setup_initial_annotations.py << 'PYEOF'
import slicer
import json

try:
    # Get layout manager
    layoutManager = slicer.app.layoutManager()
    
    initial_state = {
        "red_orientation_visible": False,
        "yellow_orientation_visible": False,
        "green_orientation_visible": False,
        "dicom_annotations_visible": True,
        "data_loaded": False
    }
    
    # Check if data is loaded
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    if volume_nodes and volume_nodes.GetNumberOfItems() > 0:
        initial_state["data_loaded"] = True
        print(f"Data loaded: {volume_nodes.GetNumberOfItems()} volume(s)")
    
    # Get current annotation state from each slice view
    for viewName in ['Red', 'Yellow', 'Green']:
        try:
            sliceWidget = layoutManager.sliceWidget(viewName)
            if sliceWidget:
                sliceNode = sliceWidget.mrmlSliceNode()
                sliceView = sliceWidget.sliceView()
                
                # Check orientation marker type
                # 0=None, 1=Cube, 2=Human, 3=Axes
                orientationType = sliceNode.GetOrientationMarkerType() if hasattr(sliceNode, 'GetOrientationMarkerType') else 0
                initial_state[f"{viewName.lower()}_orientation_type"] = orientationType
                initial_state[f"{viewName.lower()}_orientation_visible"] = orientationType > 0
                
        except Exception as e:
            print(f"Could not query {viewName} view: {e}")
    
    # Save initial state
    with open("/tmp/initial_annotation_state.json", "w") as f:
        json.dump(initial_state, f, indent=2)
    
    print("Initial annotation state recorded")
    print(json.dumps(initial_state, indent=2))
    
except Exception as e:
    print(f"Error setting up initial state: {e}")
    import traceback
    traceback.print_exc()
PYEOF

# Run the setup script in Slicer
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/setup_initial_annotations.py" &
SETUP_PID=$!
sleep 15
kill $SETUP_PID 2>/dev/null || true

# Relaunch Slicer with clean state
pkill -f "Slicer" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"
sleep 10

# Maximize window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Configure slice view display annotations for de-identified publication screenshots"
echo ""
echo "Requirements:"
echo "  1. ENABLE orientation marker labels (A/P, R/L, S/I in corners)"
echo "  2. DISABLE patient name display"
echo "  3. DISABLE date/study info display"
echo "  4. Apply to ALL slice views (Red, Yellow, Green)"
echo ""
echo "Access settings via:"
echo "  - View menu → Slice View Annotations"
echo "  - Slice controller (pin icon) → display options"
echo "  - Edit → Application Settings → Views"
echo ""