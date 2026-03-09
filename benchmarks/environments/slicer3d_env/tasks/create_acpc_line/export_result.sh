#!/bin/bash
echo "=== Exporting AC-PC Line Creation Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORT_DIR/ACPC_landmarks.mrk.json"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/acpc_final.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Initialize result variables
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0
AC_FOUND="false"
PC_FOUND="false"
LINE_FOUND="false"
AC_COORDS=""
PC_COORDS=""
ACPC_DISTANCE=""
MARKUPS_COUNT=0

# Check for output file
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE ($OUTPUT_SIZE bytes)"
fi

# If Slicer is running, try to export markups directly
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Attempting to export markups from Slicer..."
    
    cat > /tmp/export_acpc.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)
output_path = os.path.join(output_dir, "ACPC_landmarks.mrk.json")

# Collect all markups
result = {
    "fiducials": [],
    "lines": [],
    "ac_found": False,
    "pc_found": False,
    "line_found": False,
    "ac_coords": None,
    "pc_coords": None,
    "acpc_distance": None
}

# Find fiducial markups
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fiducial_nodes)} fiducial node(s)")

ac_point = None
pc_point = None

for node in fiducial_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i).lower()
        
        fid_info = {
            "node_name": node.GetName(),
            "label": node.GetNthControlPointLabel(i),
            "position_ras": pos
        }
        result["fiducials"].append(fid_info)
        print(f"  Fiducial '{fid_info['label']}': {pos}")
        
        # Check for AC
        if "ac" in label or "anterior" in label:
            result["ac_found"] = True
            result["ac_coords"] = pos
            ac_point = pos
            
        # Check for PC
        if "pc" in label or "posterior" in label:
            result["pc_found"] = True
            result["pc_coords"] = pos
            pc_point = pos

# Find line markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line node(s)")

for node in line_nodes:
    if node.GetNumberOfControlPoints() >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        line_info = {
            "name": node.GetName(),
            "p1": p1,
            "p2": p2,
            "length_mm": length
        }
        result["lines"].append(line_info)
        result["line_found"] = True
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        
        # Use line endpoints as AC/PC if not found via fiducials
        if not result["ac_found"] or not result["pc_found"]:
            # Determine which is AC (more anterior = higher Y in RAS)
            if p1[1] > p2[1]:
                if not result["ac_found"]:
                    result["ac_coords"] = p1
                    result["ac_found"] = True
                    ac_point = p1
                if not result["pc_found"]:
                    result["pc_coords"] = p2
                    result["pc_found"] = True
                    pc_point = p2
            else:
                if not result["ac_found"]:
                    result["ac_coords"] = p2
                    result["ac_found"] = True
                    ac_point = p2
                if not result["pc_found"]:
                    result["pc_coords"] = p1
                    result["pc_found"] = True
                    pc_point = p1

# Calculate AC-PC distance if both found
if ac_point and pc_point:
    dist = math.sqrt(sum((a-b)**2 for a,b in zip(ac_point, pc_point)))
    result["acpc_distance"] = dist
    print(f"AC-PC distance: {dist:.2f} mm")

# Save all markup nodes to the output file
storage_node = None
for node in list(fiducial_nodes) + list(line_nodes):
    if storage_node is None:
        # Create a markups JSON storage node
        slicer.util.saveNode(node, output_path)
        print(f"Saved markups to {output_path}")
        break

# Also save our analysis
analysis_path = "/tmp/acpc_analysis.json"
with open(analysis_path, "w") as f:
    json.dump(result, f, indent=2)
print(f"Analysis saved to {analysis_path}")
PYEOF

    # Run the export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_acpc.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export with timeout
    for i in {1..15}; do
        if [ -f /tmp/acpc_analysis.json ]; then
            echo "Export completed"
            break
        fi
        sleep 1
    done
    
    kill $EXPORT_PID 2>/dev/null || true
fi

# Parse the analysis file if it exists
if [ -f /tmp/acpc_analysis.json ]; then
    echo "Parsing analysis results..."
    
    AC_FOUND=$(python3 -c "import json; print('true' if json.load(open('/tmp/acpc_analysis.json')).get('ac_found', False) else 'false')" 2>/dev/null || echo "false")
    PC_FOUND=$(python3 -c "import json; print('true' if json.load(open('/tmp/acpc_analysis.json')).get('pc_found', False) else 'false')" 2>/dev/null || echo "false")
    LINE_FOUND=$(python3 -c "import json; print('true' if json.load(open('/tmp/acpc_analysis.json')).get('line_found', False) else 'false')" 2>/dev/null || echo "false")
    
    AC_COORDS=$(python3 -c "import json; c=json.load(open('/tmp/acpc_analysis.json')).get('ac_coords'); print(json.dumps(c) if c else 'null')" 2>/dev/null || echo "null")
    PC_COORDS=$(python3 -c "import json; c=json.load(open('/tmp/acpc_analysis.json')).get('pc_coords'); print(json.dumps(c) if c else 'null')" 2>/dev/null || echo "null")
    ACPC_DISTANCE=$(python3 -c "import json; d=json.load(open('/tmp/acpc_analysis.json')).get('acpc_distance'); print(f'{d:.2f}' if d else '0')" 2>/dev/null || echo "0")
    MARKUPS_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/acpc_analysis.json')); print(len(d.get('fiducials', [])) + len(d.get('lines', [])))" 2>/dev/null || echo "0")
fi

# Also try to parse the output markups file directly
if [ -f "$OUTPUT_FILE" ] && [ "$AC_FOUND" = "false" ] && [ "$PC_FOUND" = "false" ]; then
    echo "Attempting to parse markups file directly..."
    
    python3 << PYEOF
import json
import math
import os

output_file = "$OUTPUT_FILE"
result = {
    "ac_found": False,
    "pc_found": False,
    "line_found": False,
    "ac_coords": None,
    "pc_coords": None,
    "acpc_distance": None
}

try:
    with open(output_file) as f:
        data = json.load(f)
    
    # Slicer markups JSON format
    for markup in data.get("markups", []):
        markup_type = markup.get("type", "")
        
        for cp in markup.get("controlPoints", []):
            label = cp.get("label", "").lower()
            pos = cp.get("position", [0, 0, 0])
            
            if "ac" in label or "anterior" in label:
                result["ac_found"] = True
                result["ac_coords"] = pos
            elif "pc" in label or "posterior" in label:
                result["pc_found"] = True
                result["pc_coords"] = pos
        
        if markup_type == "Line" and len(markup.get("controlPoints", [])) >= 2:
            result["line_found"] = True
    
    # Calculate distance
    if result["ac_coords"] and result["pc_coords"]:
        ac = result["ac_coords"]
        pc = result["pc_coords"]
        dist = math.sqrt(sum((a-b)**2 for a,b in zip(ac, pc)))
        result["acpc_distance"] = dist
    
    # Save
    with open("/tmp/acpc_direct_parse.json", "w") as f:
        json.dump(result, f, indent=2)
    print("Direct parsing successful")
    
except Exception as e:
    print(f"Direct parsing failed: {e}")
PYEOF

    # Read direct parse results
    if [ -f /tmp/acpc_direct_parse.json ]; then
        AC_FOUND=$(python3 -c "import json; print('true' if json.load(open('/tmp/acpc_direct_parse.json')).get('ac_found', False) else 'false')" 2>/dev/null || echo "$AC_FOUND")
        PC_FOUND=$(python3 -c "import json; print('true' if json.load(open('/tmp/acpc_direct_parse.json')).get('pc_found', False) else 'false')" 2>/dev/null || echo "$PC_FOUND")
        LINE_FOUND=$(python3 -c "import json; print('true' if json.load(open('/tmp/acpc_direct_parse.json')).get('line_found', False) else 'false')" 2>/dev/null || echo "$LINE_FOUND")
        AC_COORDS=$(python3 -c "import json; c=json.load(open('/tmp/acpc_direct_parse.json')).get('ac_coords'); print(json.dumps(c) if c else '$AC_COORDS')" 2>/dev/null || echo "$AC_COORDS")
        PC_COORDS=$(python3 -c "import json; c=json.load(open('/tmp/acpc_direct_parse.json')).get('pc_coords'); print(json.dumps(c) if c else '$PC_COORDS')" 2>/dev/null || echo "$PC_COORDS")
        ACPC_DISTANCE=$(python3 -c "import json; d=json.load(open('/tmp/acpc_direct_parse.json')).get('acpc_distance'); print(f'{d:.2f}' if d else '$ACPC_DISTANCE')" 2>/dev/null || echo "$ACPC_DISTANCE")
    fi
fi

# Re-check output file
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
fi

# Check screenshot
SCREENSHOT_EXISTS="false"
if [ -f /tmp/acpc_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
echo "Creating result JSON..."
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "ac_found": $AC_FOUND,
    "pc_found": $PC_FOUND,
    "line_found": $LINE_FOUND,
    "ac_coords": $AC_COORDS,
    "pc_coords": $PC_COORDS,
    "acpc_distance_mm": $ACPC_DISTANCE,
    "markups_count": $MARKUPS_COUNT,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "output_path": "$OUTPUT_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/acpc_task_result.json 2>/dev/null || sudo rm -f /tmp/acpc_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/acpc_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/acpc_task_result.json
chmod 666 /tmp/acpc_task_result.json 2>/dev/null || sudo chmod 666 /tmp/acpc_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/acpc_task_result.json"
cat /tmp/acpc_task_result.json
echo ""
echo "=== Export Complete ==="