#!/bin/bash
echo "=== Exporting Define Oblique Plane Result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_DIR="/home/ga/Documents/SlicerData"
OUTPUT_FILE="$OUTPUT_DIR/acpc_plane.mrk.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Try to export plane markup from Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Attempting to export plane markup from Slicer..."
    
    cat > /tmp/export_plane.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData"
os.makedirs(output_dir, exist_ok=True)

# Find plane markup nodes
plane_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsPlaneNode")
print(f"Found {len(plane_nodes)} plane markup(s)")

plane_data = {
    "plane_count": len(plane_nodes),
    "planes": []
}

for node in plane_nodes:
    plane_info = {
        "name": node.GetName(),
        "num_control_points": node.GetNumberOfControlPoints(),
        "control_points": [],
        "normal": [0.0, 0.0, 0.0],
        "origin": [0.0, 0.0, 0.0]
    }
    
    # Get control points
    for i in range(node.GetNumberOfControlPoints()):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        plane_info["control_points"].append({
            "index": i,
            "position_ras": pos,
            "label": node.GetNthControlPointLabel(i) if node.GetNthControlPointLabel(i) else f"Point_{i}"
        })
        print(f"  Control point {i}: {pos}")
    
    # Get plane normal and origin
    normal = [0.0, 0.0, 0.0]
    origin = [0.0, 0.0, 0.0]
    try:
        node.GetNormal(normal)
        node.GetOrigin(origin)
        plane_info["normal"] = normal
        plane_info["origin"] = origin
        print(f"  Normal: {normal}")
        print(f"  Origin: {origin}")
    except Exception as e:
        print(f"  Could not get plane geometry: {e}")
    
    plane_data["planes"].append(plane_info)
    
    # Save the markup file
    mrk_path = os.path.join(output_dir, "acpc_plane.mrk.json")
    try:
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved to: {mrk_path}")
    except Exception as e:
        print(f"  Failed to save: {e}")

# Also check for any line markups (user might have used rulers)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

# Check for fiducial markups (user might have placed points first)
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fiducial_nodes)} fiducial markup(s)")

fiducial_data = []
for node in fiducial_nodes:
    for i in range(node.GetNumberOfControlPoints()):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        fiducial_data.append({
            "name": node.GetNthControlPointLabel(i),
            "position_ras": pos
        })

plane_data["fiducials"] = fiducial_data

# Save exported data
export_path = "/tmp/slicer_plane_export.json"
with open(export_path, "w") as f:
    json.dump(plane_data, f, indent=2)
print(f"Exported plane data to: {export_path}")
PYEOF

    # Run export script in Slicer
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_plane.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Check output file existence and properties
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"
NUM_CONTROL_POINTS=0
CONTROL_POINTS="[]"
PLANE_NORMAL="[0,0,0]"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE ($OUTPUT_SIZE bytes)"
    
    # Parse the markup file
    PARSED_DATA=$(python3 << 'PYEOF'
import json
import sys
import math

output_file = "/home/ga/Documents/SlicerData/acpc_plane.mrk.json"
try:
    with open(output_file, 'r') as f:
        data = json.load(f)
    
    result = {
        "num_control_points": 0,
        "control_points": [],
        "plane_normal": [0, 0, 0]
    }
    
    # Slicer markup JSON format
    if "markups" in data:
        for markup in data.get("markups", []):
            cps = markup.get("controlPoints", [])
            result["num_control_points"] = len(cps)
            for cp in cps:
                pos = cp.get("position", [0, 0, 0])
                result["control_points"].append({
                    "label": cp.get("label", ""),
                    "position_ras": pos
                })
            
            # Try to get plane normal from orientation
            if "orientation" in markup:
                # Orientation is a 4x4 matrix or quaternion
                pass
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e), "num_control_points": 0, "control_points": []}))
PYEOF
)
    
    NUM_CONTROL_POINTS=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('num_control_points', 0))" 2>/dev/null || echo "0")
    CONTROL_POINTS=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('control_points', [])))" 2>/dev/null || echo "[]")
    
    echo "Parsed: $NUM_CONTROL_POINTS control points"
fi

# Also check Slicer export data
EXPORT_DATA="{}"
if [ -f /tmp/slicer_plane_export.json ]; then
    EXPORT_DATA=$(cat /tmp/slicer_plane_export.json)
    echo "Slicer export data available"
fi

# Check for data loaded
DATA_LOADED="false"
VOLUME_NODES=0
if [ -f /tmp/slicer_export.log ]; then
    if grep -qi "MRHead\|volume" /tmp/slicer_export.log 2>/dev/null; then
        DATA_LOADED="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_size": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "num_control_points": $NUM_CONTROL_POINTS,
    "control_points": $CONTROL_POINTS,
    "slicer_export_data": $EXPORT_DATA,
    "data_loaded": $DATA_LOADED,
    "screenshot_final": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/plane_task_result.json 2>/dev/null || sudo rm -f /tmp/plane_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/plane_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/plane_task_result.json
chmod 666 /tmp/plane_task_result.json 2>/dev/null || sudo chmod 666 /tmp/plane_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer 2>/dev/null || pkill -f "Slicer" 2>/dev/null || true

echo ""
echo "Result saved to /tmp/plane_task_result.json"
cat /tmp/plane_task_result.json
echo ""
echo "=== Export Complete ==="