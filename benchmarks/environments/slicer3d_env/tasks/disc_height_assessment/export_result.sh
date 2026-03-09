#!/bin/bash
echo "=== Exporting Disc Height Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/disc_measurements.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/disc_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/disc_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_disc_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Check for line/ruler markups (used for height measurements)
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
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.2f} mm")

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "disc_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also save individual markup nodes
    for node in line_nodes:
        try:
            mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
            slicer.util.saveNode(node, mrk_path)
        except:
            pass
else:
    print("No line measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_disc_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_disc_meas" 2>/dev/null || true
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASUREMENT_COUNT=0

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/disc_measurements.mrk.json"
    "$AMOS_DIR/measurements.mrk.json"
    "/home/ga/Documents/disc_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        # Count measurements
        MEASUREMENT_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    print(len(data.get('measurements', [])))
except:
    print(0)
" 2>/dev/null || echo "0")
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_ANTERIOR=""
REPORTED_POSTERIOR=""
REPORTED_VERTEBRAL=""
REPORTED_DHI=""
REPORTED_GRADE=""
REPORTED_LEVEL=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/disc_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/disc_report.json"
    "/home/ga/disc_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        # Extract report fields
        REPORTED_ANTERIOR=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('anterior_height_mm', d.get('anterior', '')))" 2>/dev/null || echo "")
        REPORTED_POSTERIOR=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('posterior_height_mm', d.get('posterior', '')))" 2>/dev/null || echo "")
        REPORTED_VERTEBRAL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('vertebral_height_mm', d.get('vertebral', '')))" 2>/dev/null || echo "")
        REPORTED_DHI=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('disc_height_index', d.get('dhi', '')))" 2>/dev/null || echo "")
        REPORTED_GRADE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('degeneration_grade', d.get('classification', d.get('grade', ''))))" 2>/dev/null || echo "")
        REPORTED_LEVEL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('vertebral_level', d.get('level', '')))" 2>/dev/null || echo "")
        break
    fi
done

# Try to extract measurements from markup file if report doesn't have them
if [ "$MEASUREMENT_EXISTS" = "true" ] && [ -z "$REPORTED_ANTERIOR" ]; then
    echo "Attempting to extract heights from measurement markups..."
    EXTRACTED_HEIGHTS=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/Documents/SlicerData/AMOS/disc_measurements.mrk.json") as f:
        data = json.load(f)
    
    measurements = data.get("measurements", [])
    heights = {}
    
    for m in measurements:
        name = m.get("name", "").lower()
        length = m.get("length_mm", 0)
        
        if "anterior" in name or "ant" in name:
            heights["anterior"] = length
        elif "posterior" in name or "post" in name:
            heights["posterior"] = length
        elif "vertebra" in name or "body" in name or "vert" in name:
            heights["vertebral"] = length
    
    # If not named, try to infer from values
    if len(heights) < 3 and len(measurements) >= 3:
        sorted_meas = sorted(measurements, key=lambda x: x.get("length_mm", 0))
        if "posterior" not in heights:
            heights["posterior"] = sorted_meas[0].get("length_mm", 0)
        if "anterior" not in heights:
            heights["anterior"] = sorted_meas[1].get("length_mm", 0)
        if "vertebral" not in heights:
            heights["vertebral"] = sorted_meas[-1].get("length_mm", 0)
    
    print(json.dumps(heights))
except Exception as e:
    print("{}")
PYEOF
)
    
    if [ -n "$EXTRACTED_HEIGHTS" ] && [ "$EXTRACTED_HEIGHTS" != "{}" ]; then
        REPORTED_ANTERIOR=$(echo "$EXTRACTED_HEIGHTS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('anterior', ''))" 2>/dev/null || echo "")
        REPORTED_POSTERIOR=$(echo "$EXTRACTED_HEIGHTS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('posterior', ''))" 2>/dev/null || echo "")
        REPORTED_VERTEBRAL=$(echo "$EXTRACTED_HEIGHTS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('vertebral', ''))" 2>/dev/null || echo "")
        echo "Extracted: Ant=$REPORTED_ANTERIOR, Post=$REPORTED_POSTERIOR, Vert=$REPORTED_VERTEBRAL"
    fi
fi

# Check if files were created during task (anti-gaming)
MEAS_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ "$MEASUREMENT_EXISTS" = "true" ] && [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
        MEAS_CREATED_DURING_TASK="true"
    fi
fi

if [ "$REPORT_EXISTS" = "true" ] && [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${CASE_ID}_disc_gt.json" /tmp/disc_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/disc_ground_truth.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measurement_count": $MEASUREMENT_COUNT,
    "measurement_created_during_task": $MEAS_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_values": {
        "anterior_height_mm": "$REPORTED_ANTERIOR",
        "posterior_height_mm": "$REPORTED_POSTERIOR",
        "vertebral_height_mm": "$REPORTED_VERTEBRAL",
        "disc_height_index": "$REPORTED_DHI",
        "degeneration_grade": "$REPORTED_GRADE",
        "vertebral_level": "$REPORTED_LEVEL"
    },
    "screenshot_exists": $([ -f "/tmp/disc_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/disc_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/disc_task_result.json 2>/dev/null || sudo rm -f /tmp/disc_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/disc_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/disc_task_result.json
chmod 666 /tmp/disc_task_result.json 2>/dev/null || sudo chmod 666 /tmp/disc_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/disc_task_result.json
echo ""
echo "=== Export Complete ==="