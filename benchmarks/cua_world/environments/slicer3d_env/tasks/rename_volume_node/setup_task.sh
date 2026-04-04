#!/bin/bash
echo "=== Setting up Rename Volume Node task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure sample data exists
SAMPLE_DIR=$(get_sample_data_dir)
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found at $SAMPLE_FILE, attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try primary URL
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Fallback URL
    if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        wget -q -O "$SAMPLE_FILE" \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file exists and has content
if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
    echo "ERROR: Sample file not available or too small"
    exit 1
fi
echo "Sample file verified: $SAMPLE_FILE ($(du -h "$SAMPLE_FILE" | cut -f1))"

# Clean any previous task results
rm -f /tmp/rename_task_result.json 2>/dev/null || true
rm -f /tmp/initial_volumes.json 2>/dev/null || true

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with MRHead loaded
echo "Launching 3D Slicer with MRHead data..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1" &

# Wait for Slicer to start and load data
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Additional wait to ensure data is fully loaded
sleep 5

# Verify Slicer window is visible
SLICER_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1)
if [ -z "$SLICER_WINDOW" ]; then
    echo "WARNING: Slicer window not detected"
else
    echo "Slicer window detected: $SLICER_WINDOW"
    
    # Maximize and focus
    DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
fi

# Record initial state - query volume names from Slicer
echo "Recording initial volume state..."
cat > /tmp/query_initial_state.py << 'PYEOF'
import json
import slicer

# Get all volume nodes
volume_nodes = slicer.mrmlScene.GetNodesByClass("vtkMRMLScalarVolumeNode")
volume_nodes.InitTraversal()

volumes = []
node = volume_nodes.GetNextItemAsObject()
while node:
    volumes.append({
        "name": node.GetName(),
        "id": node.GetID()
    })
    node = volume_nodes.GetNextItemAsObject()

# Get all display nodes for verification
displayable_count = slicer.mrmlScene.GetNumberOfNodesByClass("vtkMRMLDisplayableNode")

result = {
    "volume_count": len(volumes),
    "volume_names": [v["name"] for v in volumes],
    "volumes": volumes,
    "displayable_count": displayable_count,
    "has_mrhead": any("MRHead" in v["name"] for v in volumes)
}

with open("/tmp/initial_volumes.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Initial state: {len(volumes)} volumes")
for v in volumes:
    print(f"  - {v['name']} ({v['id']})")
PYEOF

# Execute the query script in Slicer
echo "Querying initial volume state from Slicer..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/query_initial_state.py" > /tmp/initial_query.log 2>&1 &
QUERY_PID=$!
sleep 15
kill $QUERY_PID 2>/dev/null || true

# Check if initial state was recorded
if [ -f /tmp/initial_volumes.json ]; then
    echo "Initial state recorded:"
    cat /tmp/initial_volumes.json
else
    echo "WARNING: Could not query initial state from Slicer"
    # Create a default initial state
    cat > /tmp/initial_volumes.json << 'EOF'
{
    "volume_count": 1,
    "volume_names": ["MRHead"],
    "has_mrhead": true
}
EOF
fi

# Ensure Slicer is running (restart if the query killed it)
if ! pgrep -f "Slicer" > /dev/null 2>&1; then
    echo "Restarting Slicer with data..."
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1" &
    sleep 10
    wait_for_slicer 60
fi

# Focus and maximize Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png ga
sleep 1

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Rename the loaded volume from 'MRHead' to 'STUDY001_T1_Brain'"
echo ""
echo "Steps:"
echo "  1. Go to Data module (Modules menu > Data)"
echo "  2. Find 'MRHead' in the Subject Hierarchy tree"
echo "  3. Right-click and select 'Rename' (or double-click to edit)"
echo "  4. Enter new name: STUDY001_T1_Brain"
echo "  5. Press Enter to confirm"
echo ""