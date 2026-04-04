#!/bin/bash
echo "=== Exporting Navigate to RAS Coordinates Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot first
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
else
    echo "WARNING: 3D Slicer is not running"
fi

# Query current crosshair position from Slicer
echo "Querying crosshair position..."
cat > /tmp/export_crosshair.py << 'PYEOF'
import json
import slicer
import math

try:
    # Get the crosshair node
    crosshairNode = slicer.util.getNode('Crosshair')
    
    # Get current position
    position = [0.0, 0.0, 0.0]
    crosshairNode.GetCursorPositionRAS(position)
    
    # Check what volumes are loaded
    volumeNodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    dataLoaded = len(volumeNodes) > 0
    volumeNames = [n.GetName() for n in volumeNodes]
    
    # Target coordinates
    target_r, target_a, target_s = 12.0, -8.0, 35.0
    
    # Calculate distances from target
    dist_r = abs(position[0] - target_r)
    dist_a = abs(position[1] - target_a)
    dist_s = abs(position[2] - target_s)
    euclidean_dist = math.sqrt(dist_r**2 + dist_a**2 + dist_s**2)
    
    result = {
        "final_r": position[0],
        "final_a": position[1],
        "final_s": position[2],
        "target_r": target_r,
        "target_a": target_a,
        "target_s": target_s,
        "distance_r": dist_r,
        "distance_a": dist_a,
        "distance_s": dist_s,
        "euclidean_distance": euclidean_dist,
        "data_loaded": dataLoaded,
        "volume_names": volumeNames,
        "crosshair_query_success": True
    }
    
    with open('/tmp/crosshair_position.json', 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"Final crosshair: R={position[0]:.2f}, A={position[1]:.2f}, S={position[2]:.2f}")
    print(f"Target:          R={target_r:.2f}, A={target_a:.2f}, S={target_s:.2f}")
    print(f"Euclidean distance from target: {euclidean_dist:.2f} mm")

except Exception as e:
    result = {
        "final_r": 0.0,
        "final_a": 0.0,
        "final_s": 0.0,
        "crosshair_query_success": False,
        "error": str(e)
    }
    with open('/tmp/crosshair_position.json', 'w') as f:
        json.dump(result, f, indent=2)
    print(f"Error querying crosshair: {e}")
PYEOF

# Run the export script in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/export_crosshair.py > /tmp/slicer_export.log 2>&1 &
    SCRIPT_PID=$!
    
    # Wait for script to complete (max 20 seconds)
    for i in {1..20}; do
        if [ -f /tmp/crosshair_position.json ]; then
            break
        fi
        sleep 1
    done
    
    kill $SCRIPT_PID 2>/dev/null || true
    sleep 2
fi

# Load initial crosshair position
INITIAL_R="0.0"
INITIAL_A="0.0"
INITIAL_S="0.0"
if [ -f /tmp/initial_crosshair.json ]; then
    INITIAL_R=$(python3 -c "import json; print(json.load(open('/tmp/initial_crosshair.json')).get('initial_r', 0.0))" 2>/dev/null || echo "0.0")
    INITIAL_A=$(python3 -c "import json; print(json.load(open('/tmp/initial_crosshair.json')).get('initial_a', 0.0))" 2>/dev/null || echo "0.0")
    INITIAL_S=$(python3 -c "import json; print(json.load(open('/tmp/initial_crosshair.json')).get('initial_s', 0.0))" 2>/dev/null || echo "0.0")
fi

# Load final crosshair position
FINAL_R="0.0"
FINAL_A="0.0"
FINAL_S="0.0"
QUERY_SUCCESS="false"
EUCLIDEAN_DIST="999.0"

if [ -f /tmp/crosshair_position.json ]; then
    QUERY_SUCCESS=$(python3 -c "import json; print(str(json.load(open('/tmp/crosshair_position.json')).get('crosshair_query_success', False)).lower())" 2>/dev/null || echo "false")
    FINAL_R=$(python3 -c "import json; print(json.load(open('/tmp/crosshair_position.json')).get('final_r', 0.0))" 2>/dev/null || echo "0.0")
    FINAL_A=$(python3 -c "import json; print(json.load(open('/tmp/crosshair_position.json')).get('final_a', 0.0))" 2>/dev/null || echo "0.0")
    FINAL_S=$(python3 -c "import json; print(json.load(open('/tmp/crosshair_position.json')).get('final_s', 0.0))" 2>/dev/null || echo "0.0")
    EUCLIDEAN_DIST=$(python3 -c "import json; print(json.load(open('/tmp/crosshair_position.json')).get('euclidean_distance', 999.0))" 2>/dev/null || echo "999.0")
fi

# Calculate if position changed
POSITION_CHANGED="false"
python3 << PYEOF
import math
initial = ($INITIAL_R, $INITIAL_A, $INITIAL_S)
final = ($FINAL_R, $FINAL_A, $FINAL_S)
dist = math.sqrt(sum((a-b)**2 for a,b in zip(initial, final)))
if dist > 1.0:  # Moved more than 1mm
    print("true")
else:
    print("false")
PYEOF
POSITION_CHANGED=$(python3 -c "
import math
initial = ($INITIAL_R, $INITIAL_A, $INITIAL_S)
final = ($FINAL_R, $FINAL_A, $FINAL_S)
dist = math.sqrt(sum((a-b)**2 for a,b in zip(initial, final)))
print('true' if dist > 1.0 else 'false')
" 2>/dev/null || echo "false")

# Check data loaded status
DATA_LOADED="false"
if [ -f /tmp/crosshair_position.json ]; then
    DATA_LOADED=$(python3 -c "import json; print(str(json.load(open('/tmp/crosshair_position.json')).get('data_loaded', False)).lower())" 2>/dev/null || echo "false")
fi

# Screenshot exists check
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "crosshair_query_success": $QUERY_SUCCESS,
    "initial_r": $INITIAL_R,
    "initial_a": $INITIAL_A,
    "initial_s": $INITIAL_S,
    "final_r": $FINAL_R,
    "final_a": $FINAL_A,
    "final_s": $FINAL_S,
    "target_r": 12.0,
    "target_a": -8.0,
    "target_s": 35.0,
    "euclidean_distance_mm": $EUCLIDEAN_DIST,
    "position_changed": $POSITION_CHANGED,
    "data_loaded": $DATA_LOADED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/navigation_result.json 2>/dev/null || sudo rm -f /tmp/navigation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/navigation_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/navigation_result.json
chmod 666 /tmp/navigation_result.json 2>/dev/null || sudo chmod 666 /tmp/navigation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Navigation Result ==="
cat /tmp/navigation_result.json
echo ""
echo "=== Export Complete ==="