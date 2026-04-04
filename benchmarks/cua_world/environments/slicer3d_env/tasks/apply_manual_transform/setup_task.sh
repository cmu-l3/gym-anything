#!/bin/bash
echo "=== Setting up Apply Manual Transform task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure sample data exists
SAMPLE_DIR=$(get_sample_data_dir)
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

echo "Checking for sample data at: $SAMPLE_FILE"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found. Attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try multiple sources
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    wget -O "$SAMPLE_FILE" --timeout=120 \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || \
        echo "WARNING: Could not download sample data"
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file exists: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"
else
    echo "ERROR: Sample file not available"
fi

# Clean up any previous task state
rm -f /tmp/transform_task_result.json 2>/dev/null || true
rm -f /tmp/transform_export.json 2>/dev/null || true

# Record initial state - no transforms should exist yet
echo '{"initial_transforms": 0, "initial_volumes": 0}' > /tmp/transform_initial_state.json

# Kill any existing Slicer instances for clean start
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the MRHead volume pre-loaded
echo "Launching 3D Slicer with MRHead volume..."

if [ -f "$SAMPLE_FILE" ]; then
    # Launch Slicer with the file as argument
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"
else
    # Launch Slicer without file (agent will need to load it)
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash > /tmp/slicer_launch.log 2>&1 &"
fi

echo "Waiting for Slicer to start..."
sleep 8

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "Slicer window detected after ${i}s"
        break
    fi
    sleep 1
done

# Wait additional time for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c%s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

# Verify Slicer state by checking for volume loaded
echo "Verifying initial state..."
cat > /tmp/check_initial_state.py << 'PYEOF'
import json
import sys
try:
    import slicer
    volumes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    transforms = slicer.util.getNodesByClass('vtkMRMLLinearTransformNode')
    
    state = {
        "initial_volumes": volumes.GetNumberOfItems() if volumes else 0,
        "initial_transforms": transforms.GetNumberOfItems() if transforms else 0,
        "slicer_running": True
    }
    
    # Check if MRHead is loaded
    mrhead_loaded = False
    for i in range(volumes.GetNumberOfItems() if volumes else 0):
        node = volumes.GetItemAsObject(i)
        if node and "MRHead" in node.GetName():
            mrhead_loaded = True
            break
    state["mrhead_loaded"] = mrhead_loaded
    
    with open('/tmp/transform_initial_state.json', 'w') as f:
        json.dump(state, f, indent=2)
    
    print(f"Initial state: {state}")
except Exception as e:
    print(f"Error checking state: {e}")
    sys.exit(1)
PYEOF

# Run the check script
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/check_initial_state.py --no-main-window > /tmp/initial_check.log 2>&1 &
CHECK_PID=$!
sleep 8
kill $CHECK_PID 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Apply a 15-degree rotation around the Superior-Inferior (S) axis to correct head tilt"
echo ""
echo "STEPS:"
echo "  1. Go to Modules → Transforms"
echo "  2. Create a new Linear Transform"
echo "  3. Set rotation to ~15 degrees around IS axis (using sliders or matrix)"
echo "  4. Apply the transform to the MRHead volume"
echo "  5. Verify rotation is visible in slice views"
echo ""
echo "Sample file: $SAMPLE_FILE"
echo "Expected rotation: 15° ± 5° around S (superior-inferior) axis"