#!/bin/bash
echo "=== Exporting Measure Angle Markup Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    sudo -u ga DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORTS_DIR/angle_measurement.txt"

# Initialize result variables
SLICER_RUNNING="false"
ANGLE_MARKUP_EXISTS="false"
NUM_CONTROL_POINTS=0
ANGLE_VALUE=""
ANGLE_IN_SCENE=""
POINTS_POSITIONS="[]"
VOLUME_LOADED="false"

OUTPUT_FILE_EXISTS="false"
OUTPUT_FILE_VALUE=""
OUTPUT_FILE_MTIME="0"
FILE_CREATED_DURING_TASK="false"

# Check if Slicer is running
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
    
    # Export angle measurements from Slicer scene
    cat > /tmp/export_angle.py << 'PYEOF'
import slicer
import json
import os
import math

result = {
    "angle_markup_exists": False,
    "num_control_points": 0,
    "angle_value_degrees": None,
    "control_points": [],
    "volume_loaded": False,
    "volume_bounds": None
}

# Check if volume is loaded
volume_nodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
if volume_nodes.GetNumberOfItems() > 0:
    result["volume_loaded"] = True
    vol = volume_nodes.GetItemAsObject(0)
    bounds = [0]*6
    vol.GetBounds(bounds)
    result["volume_bounds"] = bounds
    print(f"Volume loaded with bounds: {bounds}")

# Look for angle markup nodes
angle_nodes = slicer.util.getNodesByClass('vtkMRMLMarkupsAngleNode')
print(f"Found {angle_nodes.GetNumberOfItems()} angle markup node(s)")

if angle_nodes.GetNumberOfItems() > 0:
    result["angle_markup_exists"] = True
    
    # Get the first angle node
    angle_node = angle_nodes.GetItemAsObject(0)
    
    # Get number of control points
    n_points = angle_node.GetNumberOfControlPoints()
    result["num_control_points"] = n_points
    print(f"Angle node '{angle_node.GetName()}' has {n_points} control points")
    
    # Get control point positions
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        angle_node.GetNthControlPointPosition(i, pos)
        result["control_points"].append({
            "index": i,
            "position": pos,
            "label": angle_node.GetNthControlPointLabel(i)
        })
        print(f"  Point {i}: {pos}")
    
    # Get the angle measurement
    if n_points >= 3:
        # The angle is automatically computed by Slicer
        # We can get it from the measurement
        angle_deg = angle_node.GetAngleDegrees()
        result["angle_value_degrees"] = angle_deg
        print(f"Angle measurement: {angle_deg:.2f} degrees")
    
    # Try to save the angle markup
    export_path = "/home/ga/Documents/SlicerData/Exports/angle_markup.mrk.json"
    try:
        slicer.util.saveNode(angle_node, export_path)
        result["markup_saved"] = True
        print(f"Angle markup saved to {export_path}")
    except Exception as e:
        result["markup_saved"] = False
        print(f"Could not save markup: {e}")

# Save result
result_path = "/tmp/slicer_angle_export.json"
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)
print(f"Export result saved to {result_path}")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_angle.py > /tmp/angle_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export with timeout
    for i in {1..15}; do
        if [ -f /tmp/slicer_angle_export.json ]; then
            break
        fi
        sleep 1
    done
    
    kill $EXPORT_PID 2>/dev/null || true
    
    # Parse export results
    if [ -f /tmp/slicer_angle_export.json ]; then
        ANGLE_MARKUP_EXISTS=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_angle_export.json')).get('angle_markup_exists', False) else 'false')" 2>/dev/null || echo "false")
        NUM_CONTROL_POINTS=$(python3 -c "import json; print(json.load(open('/tmp/slicer_angle_export.json')).get('num_control_points', 0))" 2>/dev/null || echo "0")
        ANGLE_IN_SCENE=$(python3 -c "import json; v=json.load(open('/tmp/slicer_angle_export.json')).get('angle_value_degrees'); print(f'{v:.2f}' if v is not None else '')" 2>/dev/null || echo "")
        VOLUME_LOADED=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_angle_export.json')).get('volume_loaded', False) else 'false')" 2>/dev/null || echo "false")
        POINTS_POSITIONS=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/slicer_angle_export.json')).get('control_points', [])))" 2>/dev/null || echo "[]")
        
        echo "Angle markup exists: $ANGLE_MARKUP_EXISTS"
        echo "Number of control points: $NUM_CONTROL_POINTS"
        echo "Angle in scene: $ANGLE_IN_SCENE degrees"
        echo "Volume loaded: $VOLUME_LOADED"
    fi
fi

# Check for user's output file
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_FILE_EXISTS="true"
    OUTPUT_FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_FILE_VALUE=$(cat "$OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]' | head -c 20)
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file exists: $OUTPUT_FILE"
    echo "Output file value: $OUTPUT_FILE_VALUE"
    echo "File created during task: $FILE_CREATED_DURING_TASK"
fi

# Also check for markup JSON file
MARKUP_FILE_EXISTS="false"
if [ -f "$EXPORTS_DIR/angle_markup.mrk.json" ]; then
    MARKUP_FILE_EXISTS="true"
    echo "Markup JSON file saved: $EXPORTS_DIR/angle_markup.mrk.json"
fi

# Check screenshot exists
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ] && [ $(stat -c%s /tmp/task_final.png 2>/dev/null || echo 0) -gt 10000 ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "volume_loaded": $VOLUME_LOADED,
    "angle_markup_exists": $ANGLE_MARKUP_EXISTS,
    "num_control_points": $NUM_CONTROL_POINTS,
    "angle_in_scene_degrees": "$ANGLE_IN_SCENE",
    "control_points": $POINTS_POSITIONS,
    "output_file_exists": $OUTPUT_FILE_EXISTS,
    "output_file_value": "$OUTPUT_FILE_VALUE",
    "output_file_mtime": $OUTPUT_FILE_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "markup_file_exists": $MARKUP_FILE_EXISTS,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/angle_task_result.json 2>/dev/null || sudo rm -f /tmp/angle_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/angle_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/angle_task_result.json
chmod 666 /tmp/angle_task_result.json 2>/dev/null || sudo chmod 666 /tmp/angle_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/angle_task_result.json:"
cat /tmp/angle_task_result.json
echo ""
echo "=== Export Complete ==="