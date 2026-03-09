#!/bin/bash
echo "=== Exporting Esophageal Wall Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_MEASUREMENT="$LIDC_DIR/esophageal_measurement.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/esophageal_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/esophageal_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_esophageal_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
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
        
        # Calculate midpoint (approximate measurement location)
        midpoint = [(a+b)/2 for a,b in zip(p1, p2)]
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "midpoint": midpoint,
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.2f} mm at position {midpoint}")

# Check for fiducial markups as well
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
    meas_path = os.path.join(output_dir, "esophageal_measurement.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also save individual markup nodes
    for node in line_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName()}_line.mrk.json")
        slicer.util.saveNode(node, mrk_path)
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer (non-blocking, short timeout)
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_esophageal_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 2
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_THICKNESS=""
MEASUREMENT_POSITION=""
MEASUREMENT_CREATED_DURING_TASK="false"

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$LIDC_DIR/esophageal_measurement.mrk.json"
    "$LIDC_DIR/measurement.mrk.json"
    "$LIDC_DIR/esophagus_measurement.mrk.json"
    "/home/ga/Documents/esophageal_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        
        # Check if created during task
        MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            MEASUREMENT_CREATED_DURING_TASK="true"
        fi
        
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Extract measurement info
        MEASURED_THICKNESS=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
measurements = data.get('measurements', [])
for m in measurements:
    if m.get('type') == 'line' and m.get('length_mm', 0) > 0:
        print(f\"{m['length_mm']:.2f}\")
        break
" 2>/dev/null || echo "")
        
        MEASUREMENT_POSITION=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
measurements = data.get('measurements', [])
for m in measurements:
    if m.get('type') == 'line' and m.get('midpoint'):
        print(str(m['midpoint']))
        break
" 2>/dev/null || echo "")
        
        echo "Measured thickness: $MEASURED_THICKNESS mm"
        echo "Position: $MEASUREMENT_POSITION"
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_THICKNESS=""
REPORTED_LEVEL=""
REPORTED_CLASSIFICATION=""
REPORTED_APPEARANCE=""
REPORTED_RECOMMENDATION=""
REPORT_CREATED_DURING_TASK="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/esophageal_report.json"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/esophagus_report.json"
    "/home/ga/Documents/esophageal_report.json"
    "/home/ga/esophageal_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Check if created during task
        MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_THICKNESS=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('measured_wall_thickness_mm', d.get('wall_thickness_mm', d.get('thickness_mm', d.get('thickness', '')))))
" 2>/dev/null || echo "")
        
        REPORTED_LEVEL=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('measurement_level', d.get('level', d.get('vertebral_level', ''))))
" 2>/dev/null || echo "")
        
        REPORTED_CLASSIFICATION=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('classification', d.get('finding', '')))
" 2>/dev/null || echo "")
        
        REPORTED_APPEARANCE=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('esophageal_appearance', d.get('appearance', '')))
" 2>/dev/null || echo "")
        
        REPORTED_RECOMMENDATION=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('recommendation', ''))
" 2>/dev/null || echo "")
        
        echo "Reported thickness: $REPORTED_THICKNESS mm"
        echo "Reported level: $REPORTED_LEVEL"
        echo "Reported classification: $REPORTED_CLASSIFICATION"
        break
    fi
done

# Screenshot exists check
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/esophageal_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_esophageal_gt.json" /tmp/esophageal_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/esophageal_ground_truth.json 2>/dev/null || true

# Copy agent report for verification
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_esophageal_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_esophageal_report.json 2>/dev/null || true
fi

# Copy agent measurement for verification
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_esophageal_measurement.json 2>/dev/null || true
    chmod 644 /tmp/agent_esophageal_measurement.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measurement_created_during_task": $MEASUREMENT_CREATED_DURING_TASK,
    "measured_thickness_mm": "$MEASURED_THICKNESS",
    "measurement_position": "$MEASUREMENT_POSITION",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_thickness_mm": "$REPORTED_THICKNESS",
    "reported_level": "$REPORTED_LEVEL",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_appearance": "$REPORTED_APPEARANCE",
    "reported_recommendation": "$REPORTED_RECOMMENDATION",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "patient_id": "$PATIENT_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/esophageal_task_result.json 2>/dev/null || sudo rm -f /tmp/esophageal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/esophageal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/esophageal_task_result.json
chmod 666 /tmp/esophageal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/esophageal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/esophageal_task_result.json
echo ""
echo "=== Export Complete ==="