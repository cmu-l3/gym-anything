#!/bin/bash
echo "=== Exporting RECIST Tumor Response Result ==="

source /workspace/scripts/task_utils.sh

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get patient number used
PATIENT_NUM=$(cat /tmp/ircadb_patient_num 2>/dev/null || echo "5")

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
OUTPUT_MEASUREMENT="$IRCADB_DIR/recist_measurements.mrk.json"
OUTPUT_REPORT="$IRCADB_DIR/recist_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/recist_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer before analysis
    cat > /tmp/export_recist_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/IRCADb"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Find all line/ruler markups (used for diameter measurement)
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
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2],
        }
        all_measurements.append(measurement)
        print(f"  Ruler '{node.GetName()}': {length:.1f} mm")

# Also check for any ruler annotations
ruler_nodes = slicer.util.getNodesByClass("vtkMRMLAnnotationRulerNode")
print(f"Found {len(ruler_nodes)} annotation ruler(s)")

for node in ruler_nodes:
    p1 = [0.0, 0.0, 0.0]
    p2 = [0.0, 0.0, 0.0]
    node.GetPosition1(p1)
    node.GetPosition2(p2)
    length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
    measurement = {
        "name": node.GetName(),
        "type": "ruler_annotation",
        "length_mm": round(length, 2),
        "p1": [round(x, 2) for x in p1],
        "p2": [round(x, 2) for x in p2],
    }
    all_measurements.append(measurement)
    print(f"  Ruler '{node.GetName()}': {length:.1f} mm")

# Save measurements if any found
if all_measurements:
    meas_path = os.path.join(output_dir, "recist_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also save each line node natively
    for node in line_nodes:
        node_path = os.path.join(output_dir, f"{node.GetName().replace(' ', '_')}.mrk.json")
        slicer.util.saveNode(node, node_path)
else:
    print("No ruler measurements found in scene")

print("Measurement export complete")
PYEOF

    # Run export in background
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_recist_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_recist_meas" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASUREMENT_COUNT="0"
MEASURED_LENGTHS=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$IRCADB_DIR/recist_measurements.mrk.json"
    "$IRCADB_DIR/measurements.mrk.json"
    "/home/ga/Documents/recist_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement file at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Extract measurement info
        MEAS_INFO=$(python3 << PYEOF
import json
try:
    with open('$path', 'r') as f:
        data = json.load(f)
    measurements = data.get('measurements', [])
    count = len([m for m in measurements if m.get('type') in ['line', 'ruler_annotation', 'ruler']])
    lengths = [m.get('length_mm', 0) for m in measurements if m.get('length_mm', 0) > 0]
    print(f"{count}|{','.join(str(round(l, 1)) for l in lengths[:5])}")
except Exception as e:
    print(f"0|")
PYEOF
)
        MEASUREMENT_COUNT=$(echo "$MEAS_INFO" | cut -d'|' -f1)
        MEASURED_LENGTHS=$(echo "$MEAS_INFO" | cut -d'|' -f2)
        echo "  Measurement count: $MEASUREMENT_COUNT"
        echo "  Lengths: $MEASURED_LENGTHS"
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_SLD=""
REPORTED_PERCENT=""
REPORTED_RESPONSE=""
REPORTED_MEASUREMENTS=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$IRCADB_DIR/recist_report.json"
    "$IRCADB_DIR/report.json"
    "/home/ga/Documents/recist_report.json"
    "/home/ga/recist_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report file at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORT_INFO=$(python3 << PYEOF
import json
try:
    with open('$path', 'r') as f:
        data = json.load(f)
    
    # Try various field names
    sld = data.get('current_sld_mm', data.get('sld', data.get('current_sld', 0)))
    pct = data.get('percent_change', data.get('change_percent', data.get('change', 0)))
    resp = data.get('response_category', data.get('response', data.get('category', ''))).upper()
    
    # Get measurements array
    meas = data.get('lesion_measurements', data.get('measurements', []))
    if isinstance(meas, list):
        meas_str = ','.join(str(round(float(m), 1)) for m in meas[:5] if m)
    else:
        meas_str = ''
    
    print(f"{sld}|{pct}|{resp}|{meas_str}")
except Exception as e:
    print(f"0|0|UNKNOWN|")
PYEOF
)
        REPORTED_SLD=$(echo "$REPORT_INFO" | cut -d'|' -f1)
        REPORTED_PERCENT=$(echo "$REPORT_INFO" | cut -d'|' -f2)
        REPORTED_RESPONSE=$(echo "$REPORT_INFO" | cut -d'|' -f3)
        REPORTED_MEASUREMENTS=$(echo "$REPORT_INFO" | cut -d'|' -f4)
        
        echo "  Reported SLD: $REPORTED_SLD mm"
        echo "  Reported percent change: $REPORTED_PERCENT%"
        echo "  Reported response: $REPORTED_RESPONSE"
        echo "  Reported measurements: $REPORTED_MEASUREMENTS"
        break
    fi
done

# Check if files were created during the task (anti-gaming)
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

# Copy files for verification
echo "Preparing files for verification..."
mkdir -p /tmp/agent_results
cp "$OUTPUT_MEASUREMENT" /tmp/agent_results/ 2>/dev/null || true
cp "$OUTPUT_REPORT" /tmp/agent_results/ 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/recist_verification_gt.json" /tmp/agent_results/ 2>/dev/null || true
chmod 666 /tmp/agent_results/* 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "elapsed_seconds": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measurement_count": $MEASUREMENT_COUNT,
    "measured_lengths": "$MEASURED_LENGTHS",
    "measurement_created_during_task": $MEAS_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_sld_mm": "$REPORTED_SLD",
    "reported_percent_change": "$REPORTED_PERCENT",
    "reported_response": "$REPORTED_RESPONSE",
    "reported_measurements": "$REPORTED_MEASUREMENTS",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "screenshot_exists": $([ -f "/tmp/recist_final.png" ] && echo "true" || echo "false"),
    "ground_truth_file": "/tmp/agent_results/recist_verification_gt.json",
    "patient_num": "$PATIENT_NUM"
}
EOF

# Move to final location
rm -f /tmp/recist_task_result.json 2>/dev/null || sudo rm -f /tmp/recist_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/recist_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/recist_task_result.json
chmod 666 /tmp/recist_task_result.json 2>/dev/null || sudo chmod 666 /tmp/recist_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/recist_task_result.json
echo ""
echo "=== Export Complete ==="