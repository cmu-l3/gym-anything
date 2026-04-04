#!/bin/bash
echo "=== Setting up Apply Color Lookup Table Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure sample data exists
SAMPLE_DIR=$(get_sample_data_dir)
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Downloading MRHead sample data..."
    mkdir -p "$SAMPLE_DIR"
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    wget -O "$SAMPLE_FILE" --timeout=120 \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "ERROR: Could not obtain sample data file"
    # Generate synthetic data as fallback
    python3 << 'PYEOF'
import numpy as np
shape = (64, 64, 64)
data = np.zeros(shape, dtype=np.int16)
center = np.array(shape) / 2
for x in range(shape[0]):
    for y in range(shape[1]):
        for z in range(shape[2]):
            dist = np.sqrt((x - center[0])**2 + (y - center[1])**2 + (z - center[2])**2)
            if dist < 25:
                data[x, y, z] = 800 + int(200 * np.sin(dist / 3))
            elif dist < 28:
                data[x, y, z] = 1200
with open('/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd', 'wb') as f:
    header = """NRRD0004
type: int16
dimension: 3
space: left-posterior-superior
sizes: 64 64 64
space directions: (2,0,0) (0,2,0) (0,0,2)
kinds: domain domain domain
endian: little
encoding: raw
space origin: (-64,-64,-64)

"""
    f.write(header.encode('ascii'))
    f.write(data.tobytes())
print("Created synthetic MRHead.nrrd")
PYEOF
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Clean up any previous task results
rm -f /tmp/color_lut_task_result.json 2>/dev/null || true
rm -f /tmp/initial_colormap.txt 2>/dev/null || true

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the sample data
echo "Launching 3D Slicer with MRHead data..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Additional wait for data to load
sleep 5

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Record initial colormap state via Slicer Python API
echo "Recording initial colormap state..."
cat > /tmp/get_initial_colormap.py << 'PYEOF'
import slicer
import json

result = {
    "volume_loaded": False,
    "volume_name": "",
    "initial_colormap": "",
    "display_node_exists": False,
    "color_node_id": ""
}

try:
    # Get all scalar volume nodes
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    
    if volume_nodes.GetNumberOfItems() > 0:
        result["volume_loaded"] = True
        volume_node = volume_nodes.GetItemAsObject(0)
        result["volume_name"] = volume_node.GetName()
        
        # Get display node
        display_node = volume_node.GetDisplayNode()
        if display_node:
            result["display_node_exists"] = True
            
            # Get color node
            color_node = display_node.GetColorNode()
            if color_node:
                result["initial_colormap"] = color_node.GetName()
                result["color_node_id"] = color_node.GetID()
    
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

# Run the Python script in Slicer
INITIAL_STATE=$(/opt/Slicer/bin/PythonSlicer /tmp/get_initial_colormap.py 2>/dev/null || echo '{"error": "failed"}')
echo "$INITIAL_STATE" > /tmp/initial_colormap_state.json
echo "Initial state: $INITIAL_STATE"

# Also save just the colormap name
INITIAL_COLORMAP=$(echo "$INITIAL_STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('initial_colormap', 'Grey'))" 2>/dev/null || echo "Grey")
echo "$INITIAL_COLORMAP" > /tmp/initial_colormap.txt
echo "Initial colormap: $INITIAL_COLORMAP"

# Take initial screenshot showing grayscale display
sleep 2
take_screenshot /tmp/task_initial.png ga
echo "Initial screenshot captured"

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot size: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Change the colormap from grayscale to a color lookup table"
echo "--------------------------------------------------------------"
echo "1. Go to Modules menu and find 'Volumes' module"
echo "2. In Display section, change 'Lookup Table' dropdown"
echo "3. Select a color LUT: Ocean, Cool, Warm, Hot, Rainbow, etc."
echo "4. The brain should now appear in colors, not grayscale"
echo ""
echo "Sample file: $SAMPLE_FILE"
echo "Initial colormap: $INITIAL_COLORMAP"