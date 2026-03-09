#!/bin/bash
echo "=== Setting up Slab MIP Configuration Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create required directories
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Prepare AMOS abdominal CT data
echo "Preparing AMOS abdominal CT data..."
/workspace/scripts/prepare_amos_data.sh 2>/dev/null || {
    echo "Warning: AMOS data preparation script had issues"
}

# Get the case ID
CASE_ID=$(cat /tmp/amos_case_id 2>/dev/null || echo "amos_0001")
CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Case ID: $CASE_ID"
echo "CT file: $CT_FILE"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    # Try alternative location
    CT_FILE=$(find "$AMOS_DIR" -name "*.nii.gz" -type f 2>/dev/null | head -1)
    if [ -z "$CT_FILE" ]; then
        echo "ERROR: No NIfTI files found in $AMOS_DIR"
        exit 1
    fi
    echo "Using alternative CT file: $CT_FILE"
fi

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true

# Launch Slicer with the CT volume
echo "Launching 3D Slicer with CT volume..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$CT_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
fi

# Record initial slab configuration via Python
echo "Recording initial slab configuration..."
cat > /tmp/record_initial_slab.py << 'PYEOF'
import slicer
import json
import os

try:
    # Get axial (Red) slice node
    sliceNode = slicer.mrmlScene.GetNodeByID('vtkMRMLSliceNodeRed')
    
    initial_state = {
        'slab_mode': -1,
        'slab_mode_name': 'Unknown',
        'slab_slices': 0,
        'slab_thickness_mm': 0,
        'slice_id': 'Red',
        'volume_loaded': False,
        'volume_spacing_z': 1.0
    }
    
    if sliceNode:
        initial_state['slab_mode'] = sliceNode.GetSlabMode()
        mode_names = {0: 'None', 1: 'Min', 2: 'Max', 3: 'Mean', 4: 'Sum'}
        initial_state['slab_mode_name'] = mode_names.get(initial_state['slab_mode'], 'Unknown')
        initial_state['slab_slices'] = sliceNode.GetSlabNumberOfSlices()
    
    # Check if volume is loaded
    volumeNode = slicer.mrmlScene.GetFirstNodeByClass('vtkMRMLScalarVolumeNode')
    if volumeNode:
        initial_state['volume_loaded'] = True
        spacing = volumeNode.GetSpacing()
        initial_state['volume_spacing_z'] = spacing[2]
        initial_state['slab_thickness_mm'] = initial_state['slab_slices'] * spacing[2]
        
        # Position slice at mid-abdomen (where aorta typically is)
        bounds = [0]*6
        volumeNode.GetBounds(bounds)
        mid_z = (bounds[4] + bounds[5]) / 2
        if sliceNode:
            sliceNode.SetSliceOffset(mid_z)
        
        # Fit slice to window
        slicer.app.layoutManager().sliceWidget('Red').sliceController().fitSliceToBackground()
    
    # Save initial state
    with open('/tmp/initial_slab_state.json', 'w') as f:
        json.dump(initial_state, f, indent=2)
    
    print(f"Initial slab state recorded: mode={initial_state['slab_mode_name']}, slices={initial_state['slab_slices']}")

except Exception as e:
    print(f"Error recording initial state: {e}")
    # Save error state
    with open('/tmp/initial_slab_state.json', 'w') as f:
        json.dump({'error': str(e), 'slab_mode': 0, 'slab_slices': 1}, f)
PYEOF

# Run the Python script in Slicer
DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/record_initial_slab.py > /tmp/slicer_init.log 2>&1 &
INIT_PID=$!
sleep 15
kill $INIT_PID 2>/dev/null || true

# Verify initial state was recorded
if [ -f /tmp/initial_slab_state.json ]; then
    echo "Initial slab state:"
    cat /tmp/initial_slab_state.json
else
    echo "Warning: Could not record initial state, creating default"
    echo '{"slab_mode": 0, "slab_mode_name": "None", "slab_slices": 1, "volume_loaded": true}' > /tmp/initial_slab_state.json
fi

# Take initial screenshot
echo "Capturing initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "Warning: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Configure the axial (red) slice view for thick-slab MIP visualization"
echo ""
echo "Instructions:"
echo "  1. Click the pin/pushpin icon in the red (axial) slice view header"
echo "  2. Find the slab mode controls"
echo "  3. Change slab mode from 'None' to 'Max' (MIP)"
echo "  4. Set slab thickness to approximately 10mm"
echo "  5. Observe vessels becoming more visible as continuous structures"
echo ""
echo "CT Volume: $CT_FILE"
echo "Target: 10mm thick slab with Maximum Intensity Projection mode"