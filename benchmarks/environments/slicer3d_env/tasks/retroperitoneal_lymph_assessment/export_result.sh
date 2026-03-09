#!/bin/bash
echo "=== Exporting Lymph Node Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get case ID
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MARKUPS="$AMOS_DIR/lymph_nodes.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/lymph_node_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/lymph_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_lymph_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Check for line/ruler markups (used for diameter measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        # Get midpoint as node location
        midpoint = [(a+b)/2 for a,b in zip(p1, p2)]
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "midpoint": midpoint
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm at {midpoint}")

# Check for fiducial markups
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        all_measurements.append({
            "name": label,
            "type": "fiducial",
            "position": pos
        })
        print(f"  Fiducial '{label}' at {pos}")

# Save measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "lymph_nodes.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also save individual nodes
    for node in line_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName().replace(' ', '_')}.mrk.json")
        slicer.util.saveNode(node, mrk_path)
else:
    print("No measurements found")

print("Export complete")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_lymph_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_lymph_meas" 2>/dev/null || true
fi

# Check for agent's markup file
MARKUPS_EXISTS="false"
MARKUPS_PATH=""
MEASUREMENTS_COUNT=0

POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MARKUPS"
    "$AMOS_DIR/lymph_nodes.mrk.json"
    "$AMOS_DIR/measurements.mrk.json"
    "$AMOS_DIR/nodes.mrk.json"
    "/home/ga/Documents/lymph_nodes.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUPS_EXISTS="true"
        MARKUPS_PATH="$path"
        echo "Found markups at: $path"
        if [ "$path" != "$OUTPUT_MARKUPS" ]; then
            cp "$path" "$OUTPUT_MARKUPS" 2>/dev/null || true
        fi
        MEASUREMENTS_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    meas = data.get('measurements', [])
    print(len([m for m in meas if m.get('type') == 'line']))
except:
    print(0)
" 2>/dev/null || echo "0")
        break
    fi
done

# Check for agent's report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_TOTAL=""
REPORTED_ENLARGED=""
REPORTED_LARGEST=""
REPORTED_N_STAGE=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/lymph_node_report.json"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/lymph_report.json"
    "/home/ga/Documents/lymph_node_report.json"
    "/home/ga/lymph_node_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        # Extract values
        REPORTED_TOTAL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('total_nodes_identified', d.get('total_nodes', '')))" 2>/dev/null || echo "")
        REPORTED_ENLARGED=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('enlarged_nodes_count', d.get('enlarged_count', '')))" 2>/dev/null || echo "")
        REPORTED_LARGEST=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('largest_node_mm', d.get('largest_mm', '')))" 2>/dev/null || echo "")
        REPORTED_N_STAGE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('n_stage', d.get('stage', '')))" 2>/dev/null || echo "")
        break
    fi
done

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if files were created during task
MARKUPS_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ "$MARKUPS_EXISTS" = "true" ] && [ -f "$OUTPUT_MARKUPS" ]; then
    MARKUPS_MTIME=$(stat -c %Y "$OUTPUT_MARKUPS" 2>/dev/null || echo "0")
    if [ "$MARKUPS_MTIME" -gt "$TASK_START" ]; then
        MARKUPS_CREATED_DURING_TASK="true"
    fi
fi

if [ "$REPORT_EXISTS" = "true" ] && [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verifier
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_lymph_nodes_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/lymph_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/lymph_ground_truth.json 2>/dev/null || true
fi

# Copy agent files for verifier
if [ -f "$OUTPUT_MARKUPS" ]; then
    cp "$OUTPUT_MARKUPS" /tmp/agent_lymph_markups.json 2>/dev/null || true
    chmod 644 /tmp/agent_lymph_markups.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_lymph_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_lymph_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "markups_exists": $MARKUPS_EXISTS,
    "markups_path": "$MARKUPS_PATH",
    "markups_created_during_task": $MARKUPS_CREATED_DURING_TASK,
    "measurements_count": $MEASUREMENTS_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_total_nodes": "$REPORTED_TOTAL",
    "reported_enlarged_count": "$REPORTED_ENLARGED",
    "reported_largest_mm": "$REPORTED_LARGEST",
    "reported_n_stage": "$REPORTED_N_STAGE",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $([ -f "/tmp/lymph_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/lymph_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/lymph_task_result.json 2>/dev/null || sudo rm -f /tmp/lymph_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/lymph_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/lymph_task_result.json
chmod 666 /tmp/lymph_task_result.json 2>/dev/null || sudo chmod 666 /tmp/lymph_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

echo ""
echo "Export result:"
cat /tmp/lymph_task_result.json
echo ""
echo "=== Export Complete ==="