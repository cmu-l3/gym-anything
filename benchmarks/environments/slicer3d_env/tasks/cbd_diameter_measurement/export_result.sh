#!/bin/bash
echo "=== Exporting CBD Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/cbd_measurement.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/cbd_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/cbd_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_cbd_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Check for line/ruler markups (used for diameter measurement)
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
            "midpoint": [(a+b)/2 for a,b in zip(p1, p2)],
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.2f} mm at midpoint {measurement['midpoint']}")

# Also check for any ROI or distance annotations
roi_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsROINode")
print(f"Found {len(roi_nodes)} ROI node(s)")

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "cbd_measurement.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Save individual markup nodes
    for node in line_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, mrk_path)
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_cbd_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_cbd_meas" 2>/dev/null || true
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_DIAMETER=""
MEASUREMENT_LOCATION=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/cbd_measurement.mrk.json"
    "$AMOS_DIR/measurement.mrk.json"
    "$AMOS_DIR/CBD.mrk.json"
    "$AMOS_DIR/cbd.mrk.json"
    "/home/ga/Documents/cbd_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        # Try to extract diameter and location from measurement
        MEAS_INFO=$(python3 << PYEOF
import json
try:
    with open('$path') as f:
        data = json.load(f)
    measurements = data.get('measurements', [])
    for m in measurements:
        if m.get('type') == 'line' and m.get('length_mm', 0) > 0:
            diameter = m['length_mm']
            midpoint = m.get('midpoint', [0, 0, 0])
            print(f"{diameter:.2f},{midpoint[0]:.1f},{midpoint[1]:.1f},{midpoint[2]:.1f}")
            break
except Exception as e:
    print(f"0,0,0,0")
PYEOF
)
        MEASURED_DIAMETER=$(echo "$MEAS_INFO" | cut -d',' -f1)
        MEAS_X=$(echo "$MEAS_INFO" | cut -d',' -f2)
        MEAS_Y=$(echo "$MEAS_INFO" | cut -d',' -f3)
        MEAS_Z=$(echo "$MEAS_INFO" | cut -d',' -f4)
        MEASUREMENT_LOCATION="$MEAS_X,$MEAS_Y,$MEAS_Z"
        echo "Measured diameter: $MEASURED_DIAMETER mm at location ($MEASUREMENT_LOCATION)"
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_DIAMETER=""
REPORTED_CLASSIFICATION=""
REPORTED_LEVEL=""
REPORTED_INTERPRETATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/cbd_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/cbd_report.json"
    "/home/ga/cbd_report.json"
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
        REPORTED_DIAMETER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('diameter_mm', d.get('diameter', d.get('cbd_diameter_mm', ''))))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', d.get('assessment', '')))" 2>/dev/null || echo "")
        REPORTED_LEVEL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('anatomical_level', d.get('level', d.get('location', ''))))" 2>/dev/null || echo "")
        REPORTED_INTERPRETATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('interpretation', d.get('clinical_interpretation', d.get('findings', ''))))" 2>/dev/null || echo "")
        echo "Report - Diameter: $REPORTED_DIAMETER, Classification: $REPORTED_CLASSIFICATION, Level: $REPORTED_LEVEL"
        break
    fi
done

# Check if measurement file was created/modified during task
MEASUREMENT_CREATED_DURING_TASK="false"
if [ "$MEASUREMENT_EXISTS" = "true" ] && [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
        MEASUREMENT_CREATED_DURING_TASK="true"
    fi
fi

# Check if report was created during task
REPORT_CREATED_DURING_TASK="false"
if [ "$REPORT_EXISTS" = "true" ] && [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Load ground truth CBD info
GT_CBD_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_cbd_gt.json"
GT_PORTA_X=""
GT_PORTA_Y=""
GT_PORTA_Z=""

if [ -f "$GT_CBD_FILE" ]; then
    GT_INFO=$(python3 << PYEOF
import json
try:
    with open('$GT_CBD_FILE') as f:
        data = json.load(f)
    ph = data.get('porta_hepatis_region_mm', [0,0,0])
    print(f"{ph[0]:.1f},{ph[1]:.1f},{ph[2]:.1f}")
except:
    print("0,0,0")
PYEOF
)
    GT_PORTA_X=$(echo "$GT_INFO" | cut -d',' -f1)
    GT_PORTA_Y=$(echo "$GT_INFO" | cut -d',' -f2)
    GT_PORTA_Z=$(echo "$GT_INFO" | cut -d',' -f3)
fi

# Copy ground truth for verification
cp "$GT_CBD_FILE" /tmp/cbd_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/cbd_ground_truth.json 2>/dev/null || true

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
    "measurement_created_during_task": $MEASUREMENT_CREATED_DURING_TASK,
    "measured_diameter_mm": "$MEASURED_DIAMETER",
    "measurement_location_mm": "$MEASUREMENT_LOCATION",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_diameter_mm": "$REPORTED_DIAMETER",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_anatomical_level": "$REPORTED_LEVEL",
    "reported_interpretation": "$REPORTED_INTERPRETATION",
    "gt_porta_hepatis_mm": "$GT_PORTA_X,$GT_PORTA_Y,$GT_PORTA_Z",
    "case_id": "$CASE_ID",
    "screenshot_exists": $([ -f "/tmp/cbd_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/cbd_task_result.json 2>/dev/null || sudo rm -f /tmp/cbd_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cbd_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/cbd_task_result.json
chmod 666 /tmp/cbd_task_result.json 2>/dev/null || sudo chmod 666 /tmp/cbd_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/cbd_task_result.json
echo ""
echo "=== Export Complete ==="