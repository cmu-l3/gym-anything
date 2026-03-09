#!/bin/bash
echo "=== Exporting Diaphragm Assessment Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MARKERS="$AMOS_DIR/diaphragm_markers.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/diaphragm_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/diaphragm_task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export markups from Slicer before closing
    cat > /tmp/export_diaphragm_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_markers = []

# Check for fiducial markups
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node.GetName()}' has {n_points} control points")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        
        marker = {
            "node_name": node.GetName(),
            "label": label,
            "position": pos,
            "z_mm": pos[2]
        }
        all_markers.append(marker)
        print(f"    Point {i}: label='{label}', z={pos[2]:.1f}mm")

# Save markers
if all_markers:
    # Create Slicer-compatible markup JSON format
    markup_json = {
        "markups": [{
            "type": "Fiducial",
            "coordinateSystem": "LPS",
            "controlPoints": [
                {
                    "id": str(i),
                    "label": m["label"],
                    "position": m["position"]
                }
                for i, m in enumerate(all_markers)
            ]
        }]
    }
    
    meas_path = os.path.join(output_dir, "diaphragm_markers.mrk.json")
    with open(meas_path, "w") as f:
        json.dump(markup_json, f, indent=2)
    print(f"Exported {len(all_markers)} markers to {meas_path}")
    
    # Also save individual nodes
    for node in fid_nodes:
        node_path = os.path.join(output_dir, f"{node.GetName()}_markups.mrk.json")
        slicer.util.saveNode(node, node_path)
else:
    print("No fiducial markers found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_diaphragm_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_diaphragm_markups" 2>/dev/null || true
fi

# Check for agent marker files
MARKERS_EXIST="false"
MARKERS_PATH=""
MARKERS_MODIFIED="false"
MARKER_COUNT=0

POSSIBLE_MARKER_PATHS=(
    "$OUTPUT_MARKERS"
    "$AMOS_DIR/diaphragm_markers.mrk.json"
    "$AMOS_DIR/F_markups.mrk.json"
    "$AMOS_DIR/Markups.mrk.json"
    "/home/ga/Documents/diaphragm_markers.mrk.json"
)

for path in "${POSSIBLE_MARKER_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKERS_EXIST="true"
        MARKERS_PATH="$path"
        echo "Found markers at: $path"
        
        # Check if created during task
        MARKER_TIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MARKER_TIME" -gt "$TASK_START" ]; then
            MARKERS_MODIFIED="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MARKERS" ]; then
            cp "$path" "$OUTPUT_MARKERS" 2>/dev/null || true
        fi
        break
    fi
done

# Extract marker data if file exists
MARKER_DATA="{}"
if [ "$MARKERS_EXIST" = "true" ] && [ -f "$MARKERS_PATH" ]; then
    MARKER_DATA=$(python3 << PYEOF
import json
import sys

try:
    with open("$MARKERS_PATH", "r") as f:
        data = json.load(f)
    
    # Parse Slicer markup JSON format
    markups = data.get("markups", [{}])
    control_points = []
    if markups:
        control_points = markups[0].get("controlPoints", [])
    
    markers = []
    for cp in control_points:
        pos = cp.get("position", [0, 0, 0])
        label = cp.get("label", "")
        markers.append({
            "label": label,
            "z": pos[2] if len(pos) > 2 else 0
        })
    
    print(json.dumps({"count": len(markers), "markers": markers}))
except Exception as e:
    print(json.dumps({"count": 0, "markers": [], "error": str(e)}))
PYEOF
)
    MARKER_COUNT=$(echo "$MARKER_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('count', 0))" 2>/dev/null || echo "0")
fi

# Check for agent report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_MODIFIED="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/diaphragm_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/diaphragm_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Check if created during task
        REPORT_TIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_TIME" -gt "$TASK_START" ]; then
            REPORT_MODIFIED="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Extract report data if file exists
REPORT_DATA="{}"
if [ "$REPORT_EXISTS" = "true" ] && [ -f "$REPORT_PATH" ]; then
    REPORT_DATA=$(cat "$REPORT_PATH" 2>/dev/null || echo "{}")
fi

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_diaphragm_gt.json" /tmp/diaphragm_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/diaphragm_ground_truth.json 2>/dev/null || true

if [ -f "$OUTPUT_MARKERS" ]; then
    cp "$OUTPUT_MARKERS" /tmp/agent_markers.json 2>/dev/null || true
    chmod 644 /tmp/agent_markers.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "diaphragm_dome_assessment@1",
    "case_id": "$CASE_ID",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "markers_file_exists": $MARKERS_EXIST,
    "markers_file_path": "$MARKERS_PATH",
    "markers_created_during_task": $MARKERS_MODIFIED,
    "marker_count": $MARKER_COUNT,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_MODIFIED,
    "screenshot_exists": $([ -f "/tmp/diaphragm_task_final.png" ] && echo "true" || echo "false"),
    "ground_truth_exists": $([ -f "/tmp/diaphragm_ground_truth.json" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="