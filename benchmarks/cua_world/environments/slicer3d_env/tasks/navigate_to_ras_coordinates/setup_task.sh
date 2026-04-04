#!/bin/bash
echo "=== Setting up Navigate to RAS Coordinates Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure sample data exists
SAMPLE_DIR=$(get_sample_data_dir)
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found. Attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try to download MRHead sample data
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    wget -O "$SAMPLE_FILE" --timeout=120 \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || \
        echo "WARNING: Could not download sample data"
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "ERROR: Sample file not available at $SAMPLE_FILE"
    exit 1
fi

echo "Sample file verified: $SAMPLE_FILE"

# Clean up any previous task results
rm -f /tmp/navigation_result.json 2>/dev/null || true
rm -f /tmp/initial_crosshair.json 2>/dev/null || true

# Kill any existing Slicer instances for clean state
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the MRHead sample
echo "Launching 3D Slicer with MRHead..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to load
sleep 5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Record initial crosshair position using Slicer Python
echo "Recording initial crosshair position..."
cat > /tmp/record_initial_crosshair.py << 'PYEOF'
import json
import slicer

try:
    # Get the crosshair node
    crosshairNode = slicer.util.getNode('Crosshair')
    
    # Get current position
    position = [0.0, 0.0, 0.0]
    crosshairNode.GetCursorPositionRAS(position)
    
    # Check if data is loaded
    volumeNodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    dataLoaded = len(volumeNodes) > 0
    volumeName = ""
    if dataLoaded:
        volumeName = volumeNodes[0].GetName()
    
    result = {
        "initial_r": position[0],
        "initial_a": position[1],
        "initial_s": position[2],
        "data_loaded": dataLoaded,
        "volume_name": volumeName,
        "timestamp": "initial"
    }
    
    with open('/tmp/initial_crosshair.json', 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"Initial crosshair position: R={position[0]:.2f}, A={position[1]:.2f}, S={position[2]:.2f}")
    print(f"Data loaded: {dataLoaded}, Volume: {volumeName}")

except Exception as e:
    # Write error state
    result = {
        "initial_r": 0.0,
        "initial_a": 0.0,
        "initial_s": 0.0,
        "data_loaded": False,
        "error": str(e)
    }
    with open('/tmp/initial_crosshair.json', 'w') as f:
        json.dump(result, f, indent=2)
    print(f"Error recording initial position: {e}")
PYEOF

# Run the Python script in Slicer
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/record_initial_crosshair.py > /tmp/slicer_init_script.log 2>&1 &
SCRIPT_PID=$!
sleep 15
kill $SCRIPT_PID 2>/dev/null || true

# Check if initial state was recorded
if [ -f /tmp/initial_crosshair.json ]; then
    echo "Initial crosshair state recorded:"
    cat /tmp/initial_crosshair.json
else
    # Create a default initial state if script failed
    echo "Creating default initial state..."
    cat > /tmp/initial_crosshair.json << EOF
{
    "initial_r": 0.0,
    "initial_a": 0.0,
    "initial_s": 0.0,
    "data_loaded": true,
    "volume_name": "MRHead",
    "timestamp": "default"
}
EOF
fi

# Set permissions
chmod 666 /tmp/initial_crosshair.json 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial screenshot..."
sleep 2
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
echo "TASK: Navigate to RAS coordinates (12, -8, 35) in the brain MRI"
echo ""
echo "The MRHead brain MRI should be loaded in 3D Slicer."
echo "Navigate the slice views so the crosshair is at:"
echo "  R (Right):    12 mm"
echo "  A (Anterior): -8 mm"  
echo "  S (Superior): 35 mm"
echo ""
echo "You can use the Python Interactor with:"
echo "  slicer.modules.markups.logic().JumpSlicesToLocation(12, -8, 35, True)"
echo ""
echo "Or use the crosshair dropdown in the toolbar."
echo ""