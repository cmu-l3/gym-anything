#!/bin/bash
echo "=== Exporting Subcarinal Lymph Node Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get patient ID
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_MEASUREMENT="$LIDC_DIR/subcarinal_measurement.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/lymph_node_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/subcarinal_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Export any measurements from Slicer
    cat > /tmp/export_ln_measurements.py << 'PYEOF'
import slicer
import json
import os
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

measurements = []

# Check for ruler/line markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        # Get z position (slice level)
        z_pos = (p1[2] + p2[2]) / 2
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "z_position_mm": z_pos
        }
        measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm at z={z_pos:.1f}")

# Also check for distance measurements via annotations
ruler_nodes = slicer.util.getNodesByClass("vtkMRMLAnnotationRulerNode")
for node in ruler_nodes:
    p1 = [0.0, 0.0, 0.0]
    p2 = [0.0, 0.0, 0.0]
    node.GetPosition1(p1)
    node.GetPosition2(p2)
    length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
    z_pos = (p1[2] + p2[2]) / 2
    measurements.append({
        "name": node.GetName(),
        "type": "ruler",
        "length_mm": length,
        "p1": list(p1),
        "p2": list(p2),
        "z_position_mm": z_pos
    })
    print(f"  Ruler '{node.GetName()}': {length:.1f} mm at z={z_pos:.1f}")

# Save measurements
if measurements:
    meas_path = os.path.join(output_dir, "subcarinal_measurement.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Exported {len(measurements)} measurements")
else:
    print("No measurements found in scene")

# Get current slice position from Red slice view
layoutManager = slicer.app.layoutManager()
redWidget = layoutManager.sliceWidget("Red")
redNode = redWidget.sliceLogic().GetSliceNode()
current_z = redNode.GetSliceOffset()
print(f"Current axial slice position: z={current_z:.1f} mm")

# Save current position info
pos_info = {
    "current_slice_z_mm": current_z,
    "measurements_count": len(measurements)
}
with open("/tmp/slicer_position_info.json", "w") as f:
    json.dump(pos_info, f)

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_ln_measurements.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_ln_measurements" 2>/dev/null || true
fi

# Check for agent's measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_LENGTH=""
MEASUREMENT_Z=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$LIDC_DIR/measurement.mrk.json"
    "$LIDC_DIR/lymphnode_measurement.mrk.json"
    "/home/ga/Documents/subcarinal_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Extract measurement info
        MEASURED_LENGTH=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
measurements = data.get('measurements', [])
for m in measurements:
    if m.get('length_mm', 0) > 0:
        print(f\"{m['length_mm']:.2f}\")
        break
" 2>/dev/null || echo "")
        
        MEASUREMENT_Z=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
measurements = data.get('measurements', [])
for m in measurements:
    if 'z_position_mm' in m:
        print(f\"{m['z_position_mm']:.2f}\")
        break
" 2>/dev/null || echo "")
        
        echo "Found measurement: $MEASURED_LENGTH mm at z=$MEASUREMENT_Z"
        break
    fi
done

# Check for agent's report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_LN_FOUND=""
REPORTED_SHORT_AXIS=""
REPORTED_CLASSIFICATION=""
REPORTED_SLICE_Z=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/ln_report.json"
    "/home/ga/Documents/lymph_node_report.json"
    "/home/ga/lymph_node_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_LN_FOUND=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
val = d.get('lymph_node_identified', d.get('lymph_node_found', d.get('ln_found', None)))
print('true' if val else 'false')
" 2>/dev/null || echo "")
        
        REPORTED_SHORT_AXIS=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
val = d.get('short_axis_mm', d.get('diameter_mm', d.get('measurement_mm', '')))
print(val if val else '')
" 2>/dev/null || echo "")
        
        REPORTED_CLASSIFICATION=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
print(d.get('classification', d.get('assessment', '')))
" 2>/dev/null || echo "")
        
        REPORTED_SLICE_Z=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
print(d.get('slice_position_mm', d.get('z_position_mm', d.get('slice_z', ''))))
" 2>/dev/null || echo "")
        
        echo "Report found: LN=$REPORTED_LN_FOUND, axis=$REPORTED_SHORT_AXIS, class=$REPORTED_CLASSIFICATION"
        break
    fi
done

# Get current slice position from Slicer if available
CURRENT_SLICE_Z=""
if [ -f /tmp/slicer_position_info.json ]; then
    CURRENT_SLICE_Z=$(python3 -c "
import json
with open('/tmp/slicer_position_info.json') as f:
    d = json.load(f)
print(f\"{d.get('current_slice_z_mm', ''):.2f}\")
" 2>/dev/null || echo "")
fi

# Check file timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

REPORT_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_station7_gt.json" /tmp/station7_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/station7_ground_truth.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measured_length_mm": "$MEASURED_LENGTH",
    "measurement_z_mm": "$MEASUREMENT_Z",
    "measurement_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_lymph_node_found": "$REPORTED_LN_FOUND",
    "reported_short_axis_mm": "$REPORTED_SHORT_AXIS",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_slice_z_mm": "$REPORTED_SLICE_Z",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "current_slice_z_mm": "$CURRENT_SLICE_Z",
    "screenshot_exists": $([ -f "/tmp/subcarinal_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/station7_ground_truth.json" ] && echo "true" || echo "false"),
    "patient_id": "$PATIENT_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/subcarinal_task_result.json 2>/dev/null || sudo rm -f /tmp/subcarinal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/subcarinal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/subcarinal_task_result.json
chmod 666 /tmp/subcarinal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/subcarinal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/subcarinal_task_result.json
echo ""
echo "=== Export Complete ==="