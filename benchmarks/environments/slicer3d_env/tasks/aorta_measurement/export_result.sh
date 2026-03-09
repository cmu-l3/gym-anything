#!/bin/bash
echo "=== Exporting Aorta Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/agent_measurement.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/aorta_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/aorta_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"

    # Try to export measurements from Slicer before closing
    cat > /tmp/export_aorta_meas.py << 'PYEOF'
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
        })

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "agent_measurement.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")

    # Also save individual markup nodes if they exist
    for node in line_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, mrk_path)
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_aorta_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_aorta_meas" 2>/dev/null || true
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_DIAMETER=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/agent_measurement.mrk.json"
    "$AMOS_DIR/measurement.mrk.json"
    "$AMOS_DIR/aorta_measurement.mrk.json"
    "/home/ga/Documents/agent_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        # Try to extract diameter from measurement
        MEASURED_DIAMETER=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
measurements = data.get('measurements', [])
for m in measurements:
    if m.get('type') == 'line' and m.get('length_mm', 0) > 0:
        print(f\"{m['length_mm']:.2f}\")
        break
" 2>/dev/null || echo "")
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_DIAMETER=""
REPORTED_CLASSIFICATION=""
REPORTED_LEVEL=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/aorta_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/aorta_report.json"
    "/home/ga/aorta_report.json"
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
        REPORTED_DIAMETER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('max_diameter_mm', d.get('diameter_mm', d.get('diameter', ''))))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', d.get('assessment', d.get('clinical_assessment', ''))))" 2>/dev/null || echo "")
        REPORTED_LEVEL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('vertebral_level', d.get('level', '')))" 2>/dev/null || echo "")
        break
    fi
done

# Use measurement diameter if report doesn't have it
if [ -z "$REPORTED_DIAMETER" ] && [ -n "$MEASURED_DIAMETER" ]; then
    REPORTED_DIAMETER="$MEASURED_DIAMETER"
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" /tmp/aorta_ground_truth.json 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz" /tmp/aorta_labels.nii.gz 2>/dev/null || true
chmod 644 /tmp/aorta_ground_truth.json /tmp/aorta_labels.nii.gz 2>/dev/null || true

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/aorta_agent_measurement.json 2>/dev/null || true
    chmod 644 /tmp/aorta_agent_measurement.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/aorta_agent_report.json 2>/dev/null || true
    chmod 644 /tmp/aorta_agent_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measured_diameter_mm": "$MEASURED_DIAMETER",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_diameter_mm": "$REPORTED_DIAMETER",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_vertebral_level": "$REPORTED_LEVEL",
    "screenshot_exists": $([ -f "/tmp/aorta_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/aorta_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/aorta_task_result.json 2>/dev/null || sudo rm -f /tmp/aorta_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/aorta_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/aorta_task_result.json
chmod 666 /tmp/aorta_task_result.json 2>/dev/null || sudo chmod 666 /tmp/aorta_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/aorta_task_result.json
echo ""
echo "=== Export Complete ==="
