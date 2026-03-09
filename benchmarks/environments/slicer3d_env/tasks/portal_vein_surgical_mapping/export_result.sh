#!/bin/bash
echo "=== Exporting Portal Vein Mapping Results ==="

source /workspace/scripts/task_utils.sh

# Get patient number
PATIENT_NUM=$(cat /tmp/ircadb_patient_num 2>/dev/null || echo "5")

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
OUTPUT_LANDMARKS="$IRCADB_DIR/portal_landmarks.mrk.json"
OUTPUT_REPORT="$IRCADB_DIR/surgical_planning_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
RESULT_FILE="/tmp/portal_mapping_result.json"

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to export any markups from Slicer
    cat > /tmp/export_portal_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/IRCADb"
os.makedirs(output_dir, exist_ok=True)

all_markups = {"measurements": [], "fiducials": []}

# Export fiducial nodes (landmarks)
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i) or f"Point_{i}"
        all_markups["fiducials"].append({
            "label": label,
            "position": pos,
            "node_name": node.GetName()
        })
        print(f"  Fiducial '{label}': {pos}")

# Export line/ruler nodes (measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler node(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        all_markups["measurements"].append({
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2
        })
        print(f"  Line '{node.GetName()}': {length:.1f} mm")

# Save markups
if all_markups["fiducials"] or all_markups["measurements"]:
    markups_path = os.path.join(output_dir, "portal_landmarks.mrk.json")
    
    # Create Slicer-compatible markup JSON
    markup_json = {
        "markups": [{
            "type": "Fiducial",
            "coordinateSystem": "LPS",
            "controlPoints": []
        }]
    }
    
    for fid in all_markups["fiducials"]:
        markup_json["markups"][0]["controlPoints"].append({
            "label": fid["label"],
            "position": fid["position"]
        })
    
    # Also add line measurements as markups
    for meas in all_markups["measurements"]:
        markup_json["measurements"] = markup_json.get("measurements", [])
        markup_json["measurements"].append(meas)
    
    with open(markups_path, "w") as f:
        json.dump(markup_json, f, indent=2)
    print(f"Saved markups to {markups_path}")
    
    # Also save individual markup files
    for node in fid_nodes:
        node_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, node_path)
else:
    print("No markups found to export")

print("Export complete")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_portal_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_portal_markups" 2>/dev/null || true
fi

# Check for landmarks file
LANDMARKS_EXISTS="false"
LANDMARKS_COUNT=0
LANDMARKS_PATH=""
LANDMARKS_DATA="{}"

POSSIBLE_LANDMARK_PATHS=(
    "$OUTPUT_LANDMARKS"
    "$IRCADB_DIR/portal_landmarks.mrk.json"
    "$IRCADB_DIR/F.mrk.json"
    "$IRCADB_DIR/Markups.mrk.json"
    "/home/ga/Documents/portal_landmarks.mrk.json"
)

for path in "${POSSIBLE_LANDMARK_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LANDMARKS_EXISTS="true"
        LANDMARKS_PATH="$path"
        echo "Found landmarks at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_LANDMARKS" ]; then
            cp "$path" "$OUTPUT_LANDMARKS" 2>/dev/null || true
        fi
        
        # Read landmarks data
        LANDMARKS_DATA=$(cat "$path" 2>/dev/null || echo "{}")
        
        # Count control points
        LANDMARKS_COUNT=$(python3 -c "
import json
try:
    with open('$path', 'r') as f:
        data = json.load(f)
    count = 0
    if 'markups' in data:
        for m in data.get('markups', []):
            count += len(m.get('controlPoints', []))
    elif 'controlPoints' in data:
        count = len(data.get('controlPoints', []))
    print(count)
except:
    print(0)
" 2>/dev/null || echo "0")
        echo "Landmarks count: $LANDMARKS_COUNT"
        break
    fi
done

# Check file modification time for anti-gaming
LANDMARKS_MODIFIED_AFTER_START="false"
if [ "$LANDMARKS_EXISTS" = "true" ] && [ -f "$OUTPUT_LANDMARKS" ]; then
    LANDMARKS_MTIME=$(stat -c %Y "$OUTPUT_LANDMARKS" 2>/dev/null || echo "0")
    if [ "$LANDMARKS_MTIME" -gt "$TASK_START" ]; then
        LANDMARKS_MODIFIED_AFTER_START="true"
        echo "Landmarks file modified after task start"
    fi
fi

# Check for surgical report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_DATA="{}"
REPORTED_DIAMETER=""
REPORTED_DISTANCE=""
REPORTED_RELATIONSHIP=""
REPORTED_RESECTABILITY=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$IRCADB_DIR/surgical_planning_report.json"
    "$IRCADB_DIR/report.json"
    "/home/ga/Documents/surgical_planning_report.json"
    "/home/ga/surgical_planning_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Read report data
        REPORT_DATA=$(cat "$path" 2>/dev/null || echo "{}")
        
        # Extract fields
        REPORTED_DIAMETER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('portal_vein_diameter_mm', ''))" 2>/dev/null || echo "")
        REPORTED_DISTANCE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('min_tumor_vessel_distance_mm', ''))" 2>/dev/null || echo "")
        REPORTED_RELATIONSHIP=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('tumor_vessel_relationship', ''))" 2>/dev/null || echo "")
        REPORTED_RESECTABILITY=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('resectability_assessment', ''))" 2>/dev/null || echo "")
        
        echo "Reported diameter: $REPORTED_DIAMETER mm"
        echo "Reported distance: $REPORTED_DISTANCE mm"
        echo "Reported relationship: $REPORTED_RELATIONSHIP"
        echo "Reported resectability: $REPORTED_RESECTABILITY"
        break
    fi
done

# Check report modification time
REPORT_MODIFIED_AFTER_START="false"
if [ "$REPORT_EXISTS" = "true" ] && [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED_AFTER_START="true"
        echo "Report file modified after task start"
    fi
fi

# Copy ground truth for verification
GT_JSON="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json"
if [ -f "$GT_JSON" ]; then
    cp "$GT_JSON" /tmp/portal_ground_truth.json
    chmod 644 /tmp/portal_ground_truth.json
    echo "Ground truth copied for verification"
fi

# Copy landmarks for verification
if [ -f "$OUTPUT_LANDMARKS" ]; then
    cp "$OUTPUT_LANDMARKS" /tmp/agent_landmarks.json
    chmod 644 /tmp/agent_landmarks.json
fi

# Copy report for verification
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json
    chmod 644 /tmp/agent_report.json
fi

# Build result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << PYEOF
import json

result = {
    "slicer_was_running": $( [ "$SLICER_RUNNING" = "true" ] && echo "true" || echo "false" ),
    "landmarks_file_exists": $( [ "$LANDMARKS_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "landmarks_file_path": "$LANDMARKS_PATH",
    "landmarks_count": $LANDMARKS_COUNT,
    "landmarks_modified_after_start": $( [ "$LANDMARKS_MODIFIED_AFTER_START" = "true" ] && echo "true" || echo "false" ),
    "report_file_exists": $( [ "$REPORT_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "report_file_path": "$REPORT_PATH",
    "report_modified_after_start": $( [ "$REPORT_MODIFIED_AFTER_START" = "true" ] && echo "true" || echo "false" ),
    "reported_diameter_mm": "$REPORTED_DIAMETER",
    "reported_distance_mm": "$REPORTED_DISTANCE",
    "reported_relationship": "$REPORTED_RELATIONSHIP",
    "reported_resectability": "$REPORTED_RESECTABILITY",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "patient_num": "$PATIENT_NUM",
    "screenshot_exists": $( [ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false" ),
    "files_modified_after_start": $( [ "$LANDMARKS_MODIFIED_AFTER_START" = "true" ] || [ "$REPORT_MODIFIED_AFTER_START" = "true" ] && echo "true" || echo "false" )
}

# Try to include landmarks data
try:
    landmarks = json.loads('''$LANDMARKS_DATA''')
    result["landmarks_data"] = landmarks
except:
    result["landmarks_data"] = {}

# Try to include report data
try:
    report = json.loads('''$REPORT_DATA''')
    result["report_data"] = report
except:
    result["report_data"] = {}

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to: $RESULT_FILE"
cat "$RESULT_FILE"