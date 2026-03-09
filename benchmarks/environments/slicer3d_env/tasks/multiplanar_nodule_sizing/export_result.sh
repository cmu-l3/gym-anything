#!/bin/bash
echo "=== Exporting Multi-planar Nodule Sizing Result ==="

source /workspace/scripts/task_utils.sh

# Get patient ID
PATIENT_ID="LIDC-IDRI-0001"
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_MEASUREMENT="$LIDC_DIR/multiplanar_measurements.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/nodule_sizing_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/multiplanar_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Export any markups from Slicer
    cat > /tmp/export_multiplanar_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Get line/ruler markups
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
        print(f"  Line '{node.GetName()}': {length:.2f} mm")

# Save measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "multiplanar_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No ruler measurements found in scene")

print("Export complete")
PYEOF
    
    # Run export in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_multiplanar_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_multiplanar_meas" 2>/dev/null || true
fi

# Check if measurement file exists
MEASUREMENT_EXISTS="false"
MEASUREMENT_COUNT=0
MEASUREMENT_PATH=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$LIDC_DIR/measurements.mrk.json"
    "$LIDC_DIR/markups.mrk.json"
    "/home/ga/Documents/multiplanar_measurements.mrk.json"
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
    with open('$path', 'r') as f:
        data = json.load(f)
    meas = data.get('measurements', [])
    print(len(meas))
except:
    print(0)
" 2>/dev/null || echo "0")
        break
    fi
done

# Check if report file exists
REPORT_EXISTS="false"
REPORT_PATH=""

# Initialize agent measurement variables
AGENT_AXIAL="null"
AGENT_CORONAL="null"
AGENT_SAGITTAL="null"
AGENT_MAX="null"
AGENT_MIN="null"
AGENT_ASPHERICITY="null"
AGENT_DISCREPANT="null"
AGENT_SHAPE="null"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/sizing_report.json"
    "/home/ga/Documents/nodule_sizing_report.json"
    "/home/ga/nodule_sizing_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract agent's values
        AGENT_AXIAL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('axial_diameter_mm', d.get('axial_mm', 'null')))" 2>/dev/null || echo "null")
        AGENT_CORONAL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('coronal_diameter_mm', d.get('coronal_mm', 'null')))" 2>/dev/null || echo "null")
        AGENT_SAGITTAL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('sagittal_diameter_mm', d.get('sagittal_mm', 'null')))" 2>/dev/null || echo "null")
        AGENT_MAX=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('maximum_diameter_mm', d.get('max_diameter_mm', d.get('max_diameter', 'null'))))" 2>/dev/null || echo "null")
        AGENT_MIN=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('minimum_diameter_mm', d.get('min_diameter_mm', d.get('min_diameter', 'null'))))" 2>/dev/null || echo "null")
        AGENT_ASPHERICITY=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('asphericity_percent', d.get('asphericity', 'null')))" 2>/dev/null || echo "null")
        AGENT_DISCREPANT=$(python3 -c "import json; d=json.load(open('$path')); v=d.get('discrepancy_flag', d.get('discrepant', None)); print(str(v).lower() if v is not None else 'null')" 2>/dev/null || echo "null")
        AGENT_SHAPE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('shape_classification', d.get('shape', 'null')))" 2>/dev/null || echo "null")
        break
    fi
done

# Check file timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ "$REPORT_EXISTS" = "true" ] && [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

MEAS_CREATED_DURING_TASK="false"
if [ "$MEASUREMENT_EXISTS" = "true" ] && [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
        MEAS_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_multiplanar_gt.json" /tmp/multiplanar_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/multiplanar_ground_truth.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measurement_count": $MEASUREMENT_COUNT,
    "measurement_created_during_task": $MEAS_CREATED_DURING_TASK,
    "report_file_exists": $REPORT_EXISTS,
    "report_created_during_task": $FILE_CREATED_DURING_TASK,
    "agent_measurements": {
        "axial_mm": $AGENT_AXIAL,
        "coronal_mm": $AGENT_CORONAL,
        "sagittal_mm": $AGENT_SAGITTAL,
        "max_diameter_mm": $AGENT_MAX,
        "min_diameter_mm": $AGENT_MIN,
        "asphericity_percent": $AGENT_ASPHERICITY,
        "discrepancy_flag": $AGENT_DISCREPANT,
        "shape_classification": "$AGENT_SHAPE"
    },
    "screenshot_exists": $([ -f /tmp/multiplanar_final.png ] && echo "true" || echo "false"),
    "patient_id": "$PATIENT_ID"
}
EOF

# Save result
rm -f /tmp/multiplanar_task_result.json 2>/dev/null || sudo rm -f /tmp/multiplanar_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/multiplanar_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/multiplanar_task_result.json
chmod 666 /tmp/multiplanar_task_result.json 2>/dev/null || sudo chmod 666 /tmp/multiplanar_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/multiplanar_task_result.json
echo ""
echo "=== Export Complete ==="