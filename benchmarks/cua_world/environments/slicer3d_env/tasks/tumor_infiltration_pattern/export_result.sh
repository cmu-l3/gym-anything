#!/bin/bash
echo "=== Exporting Tumor Infiltration Pattern Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_MARKUPS="$BRATS_DIR/infiltration_markups.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/infiltration_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/infiltration_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export markups from Slicer
    cat > /tmp/export_infiltration_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Check for line/ruler markups
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
        print(f"  Line '{node.GetName()}': {length:.1f} mm")

# Check for fiducial markups
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        all_measurements.append({
            "name": node.GetNthControlPointLabel(i),
            "type": "fiducial",
            "position": [round(x, 2) for x in pos],
        })

# Save measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "infiltration_markups.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also save individual markup nodes
    for node in line_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, mrk_path)
else:
    print("No measurements found in scene")

print("Markup export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_infiltration_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_infiltration_markups" 2>/dev/null || true
fi

# Check if agent saved markups file
MARKUPS_EXISTS="false"
MARKUPS_PATH=""
MEASUREMENT_COUNT=0
MAX_MEASUREMENT_MM=""

POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MARKUPS"
    "$BRATS_DIR/infiltration_markups.mrk.json"
    "$BRATS_DIR/markups.mrk.json"
    "$BRATS_DIR/measurements.mrk.json"
    "/home/ga/Documents/infiltration_markups.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUPS_EXISTS="true"
        MARKUPS_PATH="$path"
        echo "Found markups at: $path"
        if [ "$path" != "$OUTPUT_MARKUPS" ]; then
            cp "$path" "$OUTPUT_MARKUPS" 2>/dev/null || true
        fi
        
        # Extract measurement info
        MEASUREMENT_COUNT=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurements', [])
line_meas = [m for m in meas if m.get('type') == 'line']
print(len(line_meas))
" 2>/dev/null || echo "0")
        
        MAX_MEASUREMENT_MM=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurements', [])
line_lengths = [m.get('length_mm', 0) for m in meas if m.get('type') == 'line']
if line_lengths:
    print(f'{max(line_lengths):.2f}')
else:
    print('')
" 2>/dev/null || echo "")
        
        echo "Measurement count: $MEASUREMENT_COUNT"
        echo "Max measurement: $MAX_MEASUREMENT_MM mm"
        break
    fi
done

# Check if agent saved report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_INDEX=""
REPORTED_RADIUS=""
REPORTED_GRADE=""
REPORTED_BORDER=""
REPORTED_STRUCTURES=""
REPORT_COMPLETE="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/infiltration_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/infiltration_report.json"
    "/home/ga/infiltration_report.json"
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
        REPORTED_INDEX=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('infiltration_index', ''))" 2>/dev/null || echo "")
        REPORTED_RADIUS=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('max_infiltration_radius_mm', ''))" 2>/dev/null || echo "")
        REPORTED_GRADE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('infiltration_grade', ''))" 2>/dev/null || echo "")
        REPORTED_BORDER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('border_characterization', ''))" 2>/dev/null || echo "")
        REPORTED_STRUCTURES=$(python3 -c "import json; d=json.load(open('$path')); print(','.join(d.get('infiltrated_structures', [])))" 2>/dev/null || echo "")
        
        # Check report completeness
        REPORT_COMPLETE=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
required = ['border_characterization', 'infiltrated_structures', 'max_infiltration_radius_mm', 
            'infiltration_index', 'infiltration_grade']
complete = all(k in d and d[k] for k in required)
print('true' if complete else 'false')
" 2>/dev/null || echo "false")
        
        echo "Report fields:"
        echo "  - Infiltration index: $REPORTED_INDEX"
        echo "  - Max radius: $REPORTED_RADIUS mm"
        echo "  - Grade: $REPORTED_GRADE"
        echo "  - Border: $REPORTED_BORDER"
        echo "  - Structures: $REPORTED_STRUCTURES"
        echo "  - Complete: $REPORT_COMPLETE"
        break
    fi
done

# Check file timestamps for anti-gaming
MARKUPS_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_MARKUPS" ]; then
    MARKUP_MTIME=$(stat -c %Y "$OUTPUT_MARKUPS" 2>/dev/null || echo "0")
    if [ "$MARKUP_MTIME" -gt "$TASK_START" ]; then
        MARKUPS_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_infiltration_gt.json" /tmp/infiltration_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/infiltration_ground_truth.json 2>/dev/null || true

if [ -f "$OUTPUT_MARKUPS" ]; then
    cp "$OUTPUT_MARKUPS" /tmp/agent_markups.json 2>/dev/null || true
    chmod 644 /tmp/agent_markups.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "markups_exists": $MARKUPS_EXISTS,
    "markups_created_during_task": $MARKUPS_CREATED_DURING_TASK,
    "measurement_count": $MEASUREMENT_COUNT,
    "max_measurement_mm": "$MAX_MEASUREMENT_MM",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_complete": $REPORT_COMPLETE,
    "reported_infiltration_index": "$REPORTED_INDEX",
    "reported_max_radius_mm": "$REPORTED_RADIUS",
    "reported_grade": "$REPORTED_GRADE",
    "reported_border": "$REPORTED_BORDER",
    "reported_structures": "$REPORTED_STRUCTURES",
    "screenshot_exists": $([ -f "/tmp/infiltration_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/infiltration_ground_truth.json" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/infiltration_task_result.json 2>/dev/null || sudo rm -f /tmp/infiltration_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/infiltration_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/infiltration_task_result.json
chmod 666 /tmp/infiltration_task_result.json 2>/dev/null || sudo chmod 666 /tmp/infiltration_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/infiltration_task_result.json
echo ""
echo "=== Export Complete ==="