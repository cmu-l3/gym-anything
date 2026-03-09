#!/bin/bash
echo "=== Exporting Azygos Vein Diameter Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_MEASUREMENT="$LIDC_DIR/azygos_measurement.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/azygos_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/azygos_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"

    # Try to export measurements from Slicer before closing
    cat > /tmp/export_azygos_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
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
        
        # Calculate centroid of measurement
        centroid = [(a+b)/2 for a,b in zip(p1, p2)]
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "centroid": centroid,
            "z_coordinate": centroid[2]
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm at z={centroid[2]:.1f}")

        # Save individual markup
        mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, mrk_path)

# Check for fiducial markups too
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
            "position": pos,
            "z_coordinate": pos[2]
        })

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "azygos_measurement.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_azygos_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_azygos_meas" 2>/dev/null || true
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_DIAMETER=""
MEASUREMENT_Z=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$LIDC_DIR/azygos_measurement.mrk.json"
    "$LIDC_DIR/measurement.mrk.json"
    "$LIDC_DIR/L.mrk.json"
    "$LIDC_DIR/Line.mrk.json"
    "/home/ga/Documents/azygos_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        # Try to extract diameter and z-coordinate from measurement
        read MEASURED_DIAMETER MEASUREMENT_Z < <(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
measurements = data.get('measurements', [])
for m in measurements:
    if m.get('type') == 'line' and m.get('length_mm', 0) > 0:
        print(f\"{m['length_mm']:.2f} {m.get('z_coordinate', 0):.2f}\")
        break
else:
    print('0 0')
" 2>/dev/null || echo "0 0")
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
    "$LIDC_DIR/azygos_report.json"
    "$LIDC_DIR/report.json"
    "/home/ga/Documents/azygos_report.json"
    "/home/ga/azygos_report.json"
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
        REPORTED_DIAMETER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('diameter_mm', d.get('diameter', '')))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', ''))" 2>/dev/null || echo "")
        REPORTED_LEVEL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('slice_level', d.get('level', '')))" 2>/dev/null || echo "")
        REPORTED_INTERPRETATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('interpretation', d.get('clinical_interpretation', '')))" 2>/dev/null || echo "")
        echo "Reported diameter: $REPORTED_DIAMETER mm"
        echo "Reported classification: $REPORTED_CLASSIFICATION"
        echo "Reported level: $REPORTED_LEVEL"
        break
    fi
done

# Check file timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ "$MEASUREMENT_EXISTS" = "true" ] && [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Measurement file created during task"
    fi
fi

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_azygos_gt.json" /tmp/azygos_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/azygos_ground_truth.json 2>/dev/null || true

# Take another screenshot showing final state
take_screenshot /tmp/azygos_final2.png ga

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
    "measured_diameter_mm": "$MEASURED_DIAMETER",
    "measurement_z_coordinate": "$MEASUREMENT_Z",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_diameter_mm": "$REPORTED_DIAMETER",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_slice_level": "$REPORTED_LEVEL",
    "reported_interpretation": "$REPORTED_INTERPRETATION",
    "patient_id": "$PATIENT_ID",
    "screenshot_exists": $([ -f "/tmp/azygos_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/azygos_task_result.json 2>/dev/null || sudo rm -f /tmp/azygos_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/azygos_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/azygos_task_result.json
chmod 666 /tmp/azygos_task_result.json 2>/dev/null || sudo chmod 666 /tmp/azygos_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/azygos_task_result.json
echo ""
echo "=== Export Complete ==="