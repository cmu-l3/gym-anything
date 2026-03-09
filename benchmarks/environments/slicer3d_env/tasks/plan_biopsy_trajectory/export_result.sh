#!/bin/bash
echo "=== Exporting Plan Biopsy Trajectory results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/trajectory_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
else
    echo "Warning: 3D Slicer is not running"
fi

# Initialize markup data
MARKUP_EXISTS="false"
MARKUP_NAME=""
MARKUP_TYPE=""
NUM_CONTROL_POINTS=0
CONTROL_POINTS_JSON="[]"
LINE_LENGTH_MM=0
ALL_MARKUPS_JSON="[]"
EXTRACTION_ERROR=""

# Extract markup data from Slicer using Python
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting markup data from Slicer..."
    
    # Create extraction script
    cat > /tmp/extract_trajectory_markup.py << 'PYEOF'
import json
import sys
import math

result = {
    "markup_exists": False,
    "markup_name": None,
    "markup_type": None,
    "num_control_points": 0,
    "control_points_ras": [],
    "line_length_mm": 0,
    "all_markups": [],
    "error": None
}

try:
    import slicer
    
    # Get all markup nodes
    markup_nodes = []
    
    # Try different markup node classes
    for node_class in ["vtkMRMLMarkupsLineNode", "vtkMRMLMarkupsCurveNode", "vtkMRMLMarkupsFiducialNode"]:
        try:
            nodes = slicer.util.getNodesByClass(node_class)
            if nodes:
                markup_nodes.extend(nodes)
        except:
            pass
    
    # Also try generic markups node
    try:
        generic_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsNode")
        for node in generic_nodes:
            if node not in markup_nodes:
                markup_nodes.append(node)
    except:
        pass
    
    # Process all markup nodes
    for node in markup_nodes:
        node_info = {
            "name": node.GetName(),
            "type": node.GetClassName(),
            "num_points": node.GetNumberOfControlPoints()
        }
        result["all_markups"].append(node_info)
    
    # Find the biopsy trajectory markup (by name or by having 2 points)
    target_node = None
    
    # First priority: find by name
    for node in markup_nodes:
        name_lower = node.GetName().lower()
        if "biopsy" in name_lower or "trajectory" in name_lower:
            target_node = node
            break
    
    # Second priority: find line node with 2 points
    if target_node is None:
        for node in markup_nodes:
            if "line" in node.GetClassName().lower() and node.GetNumberOfControlPoints() == 2:
                target_node = node
                break
    
    # Third priority: any node with exactly 2 points
    if target_node is None:
        for node in markup_nodes:
            if node.GetNumberOfControlPoints() == 2:
                target_node = node
                break
    
    # Extract data from target node
    if target_node is not None:
        result["markup_exists"] = True
        result["markup_name"] = target_node.GetName()
        result["markup_type"] = target_node.GetClassName()
        result["num_control_points"] = target_node.GetNumberOfControlPoints()
        
        # Get control point coordinates
        points = []
        for i in range(target_node.GetNumberOfControlPoints()):
            pos = [0.0, 0.0, 0.0]
            target_node.GetNthControlPointPositionWorld(i, pos)
            points.append(pos)
        result["control_points_ras"] = points
        
        # Calculate line length if 2+ points
        if len(points) >= 2:
            dx = points[1][0] - points[0][0]
            dy = points[1][1] - points[0][1]
            dz = points[1][2] - points[0][2]
            result["line_length_mm"] = math.sqrt(dx*dx + dy*dy + dz*dz)

except Exception as e:
    result["error"] = str(e)

# Output as JSON
print(json.dumps(result))
PYEOF

    # Try to run the extraction script via Slicer's Python
    # Method 1: Direct Python script execution
    MARKUP_JSON=$(/opt/Slicer/bin/PythonSlicer /tmp/extract_trajectory_markup.py 2>/dev/null | tail -1)
    
    # Check if we got valid JSON
    if [ -n "$MARKUP_JSON" ] && echo "$MARKUP_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        echo "Successfully extracted markup data"
        echo "$MARKUP_JSON" > /tmp/markup_data.json
        
        # Parse the JSON
        MARKUP_EXISTS=$(echo "$MARKUP_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('markup_exists') else 'false')" 2>/dev/null || echo "false")
        MARKUP_NAME=$(echo "$MARKUP_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('markup_name') or '')" 2>/dev/null || echo "")
        MARKUP_TYPE=$(echo "$MARKUP_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('markup_type') or '')" 2>/dev/null || echo "")
        NUM_CONTROL_POINTS=$(echo "$MARKUP_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('num_control_points', 0))" 2>/dev/null || echo "0")
        CONTROL_POINTS_JSON=$(echo "$MARKUP_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('control_points_ras', [])))" 2>/dev/null || echo "[]")
        LINE_LENGTH_MM=$(echo "$MARKUP_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('line_length_mm', 0))" 2>/dev/null || echo "0")
        ALL_MARKUPS_JSON=$(echo "$MARKUP_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('all_markups', [])))" 2>/dev/null || echo "[]")
    else
        echo "Warning: Could not extract markup data via PythonSlicer"
        EXTRACTION_ERROR="PythonSlicer extraction failed"
        
        # Save empty markup data
        echo '{"markup_exists": false, "error": "extraction_failed"}' > /tmp/markup_data.json
    fi
else
    echo "Slicer not running - cannot extract markup data"
    EXTRACTION_ERROR="Slicer not running"
    echo '{"markup_exists": false, "error": "slicer_not_running"}' > /tmp/markup_data.json
fi

# Check screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
if [ -f /tmp/trajectory_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c%s /tmp/trajectory_final.png 2>/dev/null || echo "0")
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "sample_id": "$SAMPLE_ID",
    "markup_exists": $MARKUP_EXISTS,
    "markup_name": "$MARKUP_NAME",
    "markup_type": "$MARKUP_TYPE",
    "num_control_points": $NUM_CONTROL_POINTS,
    "control_points_ras": $CONTROL_POINTS_JSON,
    "line_length_mm": $LINE_LENGTH_MM,
    "all_markups": $ALL_MARKUPS_JSON,
    "extraction_error": "$EXTRACTION_ERROR",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "ground_truth_file": "$GROUND_TRUTH_DIR/${SAMPLE_ID}_trajectory_gt.json"
}
EOF

# Move to final location with permission handling
rm -f /tmp/trajectory_task_result.json 2>/dev/null || sudo rm -f /tmp/trajectory_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/trajectory_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/trajectory_task_result.json
chmod 666 /tmp/trajectory_task_result.json 2>/dev/null || sudo chmod 666 /tmp/trajectory_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/trajectory_task_result.json"
cat /tmp/trajectory_task_result.json
echo ""
echo "=== Export complete ==="