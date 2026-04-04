#!/bin/bash
echo "=== Exporting IVC Diameter Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/ivc_measurements.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/ivc_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing for anti-gaming verification
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/ivc_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_ivc_meas.py << 'PYEOF'
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
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm")
        
        # Also try to save the node directly
        try:
            mrk_path = os.path.join(output_dir, f"{node.GetName().replace(' ', '_')}.mrk.json")
            slicer.util.saveNode(node, mrk_path)
        except:
            pass

# Save combined measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "ivc_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"markups": all_measurements, "measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No line measurements found in scene")

print("Export complete")
PYEOF
    
    # Run the export script in Slicer (brief background run)
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_ivc_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    sleep 8
    kill $EXPORT_PID 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENTS_EXIST="false"
MEASUREMENTS_PATH=""
MEASUREMENTS_TIME="0"
MEASUREMENT_COUNT=0

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/ivc_measurements.mrk.json"
    "$AMOS_DIR/measurements.mrk.json"
    "$AMOS_DIR/L.mrk.json"
    "$AMOS_DIR/Line.mrk.json"
    "/home/ga/Documents/ivc_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENTS_EXIST="true"
        MEASUREMENTS_PATH="$path"
        MEASUREMENTS_TIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found measurements at: $path"
        
        # Count measurements and extract lengths
        MEASUREMENT_COUNT=$(python3 -c "
import json
try:
    with open('$path', 'r') as f:
        data = json.load(f)
    markups = data.get('markups', data.get('measurements', []))
    count = 0
    for m in markups:
        if m.get('type') == 'line' or m.get('type') == 'Line':
            count += 1
        elif m.get('controlPoints'):  # Slicer native markup format
            count += 1
    print(count)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        break
    fi
done

# Validate measurement was created during task
MEASUREMENTS_VALID="false"
if [ "$MEASUREMENTS_EXIST" = "true" ] && [ "$MEASUREMENTS_TIME" -gt "$TASK_START" ]; then
    MEASUREMENTS_VALID="true"
    echo "Measurements created during task (valid)"
else
    echo "Measurements may have pre-existed task"
fi

# Check for report file
REPORT_EXIST="false"
REPORT_PATH=""
CLASSIFICATION=""
INTRAHEPATIC_REPORTED=""
INFRARENAL_REPORTED=""
MORPHOLOGY_REPORTED=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/ivc_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/ivc_report.json"
    "/home/ga/ivc_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXIST="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Extract report fields
        CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', ''))" 2>/dev/null || echo "")
        INTRAHEPATIC_REPORTED=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('intrahepatic_diameter_mm', d.get('intrahepatic', '')))" 2>/dev/null || echo "")
        INFRARENAL_REPORTED=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('infrarenal_diameter_mm', d.get('infrarenal', '')))" 2>/dev/null || echo "")
        MORPHOLOGY_REPORTED=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('morphology', 'Normal'))" 2>/dev/null || echo "Normal")
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Also try to extract diameters from measurement file if report doesn't have them
if [ -z "$INTRAHEPATIC_REPORTED" ] && [ "$MEASUREMENTS_EXIST" = "true" ]; then
    # Get measurement lengths sorted by size (largest is typically intrahepatic)
    DIAMETERS=$(python3 -c "
import json
try:
    with open('$MEASUREMENTS_PATH', 'r') as f:
        data = json.load(f)
    markups = data.get('markups', data.get('measurements', []))
    lengths = []
    for m in markups:
        if 'length_mm' in m:
            lengths.append(m['length_mm'])
        elif 'controlPoints' in m and len(m['controlPoints']) >= 2:
            import math
            p1 = m['controlPoints'][0].get('position', [0,0,0])
            p2 = m['controlPoints'][1].get('position', [0,0,0])
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            lengths.append(length)
    lengths.sort(reverse=True)
    if len(lengths) >= 2:
        print(f'{lengths[0]:.2f},{lengths[1]:.2f}')
    elif len(lengths) == 1:
        print(f'{lengths[0]:.2f},')
except:
    print(',')
" 2>/dev/null || echo ",")
    
    MEASURED_INTRAHEPATIC=$(echo "$DIAMETERS" | cut -d',' -f1)
    MEASURED_INFRARENAL=$(echo "$DIAMETERS" | cut -d',' -f2)
    
    if [ -n "$MEASURED_INTRAHEPATIC" ]; then
        echo "Extracted intrahepatic from measurements: $MEASURED_INTRAHEPATIC mm"
    fi
    if [ -n "$MEASURED_INFRARENAL" ]; then
        echo "Extracted infrarenal from measurements: $MEASURED_INFRARENAL mm"
    fi
else
    MEASURED_INTRAHEPATIC="$INTRAHEPATIC_REPORTED"
    MEASURED_INFRARENAL="$INFRARENAL_REPORTED"
fi

# Copy ground truth for verification
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_ivc_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/ivc_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/ivc_ground_truth.json 2>/dev/null || true
fi

# Copy screenshots
cp /tmp/ivc_initial.png /tmp/task_initial.png 2>/dev/null || true
cp /tmp/ivc_final.png /tmp/task_final.png 2>/dev/null || true

# Copy measurement file for verification
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/ivc_measurements.mrk.json 2>/dev/null || true
    chmod 644 /tmp/ivc_measurements.mrk.json 2>/dev/null || true
fi

# Copy report file for verification
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/ivc_report.json 2>/dev/null || true
    chmod 644 /tmp/ivc_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "measurements_exist": $MEASUREMENTS_EXIST,
    "measurements_valid": $MEASUREMENTS_VALID,
    "measurements_file": "$MEASUREMENTS_PATH",
    "measurements_time": $MEASUREMENTS_TIME,
    "measurement_count": $MEASUREMENT_COUNT,
    "report_exist": $REPORT_EXIST,
    "report_file": "$REPORT_PATH",
    "classification_reported": "$CLASSIFICATION",
    "intrahepatic_reported": "$INTRAHEPATIC_REPORTED",
    "infrarenal_reported": "$INFRARENAL_REPORTED",
    "morphology_reported": "$MORPHOLOGY_REPORTED",
    "measured_intrahepatic": "$MEASURED_INTRAHEPATIC",
    "measured_infrarenal": "$MEASURED_INFRARENAL",
    "case_id": "$CASE_ID",
    "screenshot_final": "/tmp/ivc_final.png",
    "ground_truth_file": "/tmp/ivc_ground_truth.json"
}
EOF

# Save result
rm -f /tmp/ivc_task_result.json 2>/dev/null || sudo rm -f /tmp/ivc_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ivc_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ivc_task_result.json
chmod 666 /tmp/ivc_task_result.json 2>/dev/null || sudo chmod 666 /tmp/ivc_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/ivc_task_result.json
echo ""
echo "=== Export Complete ==="