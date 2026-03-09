#!/bin/bash
echo "=== Exporting Tracheal Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get patient ID
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_MEASUREMENT="$LIDC_DIR/tracheal_measurement.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/tracheal_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/tracheal_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_tracheal_meas.py << 'PYEOF'
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
        
        # Get midpoint for location
        midpoint = [(a+b)/2 for a,b in zip(p1, p2)]
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "midpoint": midpoint,
            "z_coordinate": midpoint[2]
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm at z={midpoint[2]:.1f}")

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
            "position": pos,
        })

# Save measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "tracheal_measurement.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also save individual markup nodes
    for node in line_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, mrk_path)
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_tracheal_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_tracheal_meas" 2>/dev/null || true
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_DIAMETER=""
MEASUREMENT_Z=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$LIDC_DIR/measurement.mrk.json"
    "$LIDC_DIR/trachea_measurement.mrk.json"
    "/home/ga/Documents/tracheal_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        
        # Check if created during task (anti-gaming)
        MEAS_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
            MEASUREMENT_CREATED_DURING_TASK="true"
        else
            MEASUREMENT_CREATED_DURING_TASK="false"
        fi
        
        echo "Found measurement at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Extract diameter from measurement
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

        # Extract z-coordinate
        MEASUREMENT_Z=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
measurements = data.get('measurements', [])
for m in measurements:
    if m.get('type') == 'line':
        z = m.get('z_coordinate', m.get('midpoint', [0,0,0])[2])
        print(f\"{z:.1f}\")
        break
" 2>/dev/null || echo "")
        break
    fi
done

# Default if not set
MEASUREMENT_CREATED_DURING_TASK="${MEASUREMENT_CREATED_DURING_TASK:-false}"

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_DIAMETER=""
REPORTED_ETT=""
REPORTED_SHAPE=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/airway_report.json"
    "/home/ga/Documents/tracheal_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        
        # Check if created during task
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        else
            REPORT_CREATED_DURING_TASK="false"
        fi
        
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_DIAMETER=$(python3 -c "
import json
d = json.load(open('$path'))
diam = d.get('tracheal_diameter_mm', d.get('diameter_mm', d.get('diameter', '')))
print(diam)
" 2>/dev/null || echo "")
        
        REPORTED_ETT=$(python3 -c "
import json
d = json.load(open('$path'))
ett = d.get('recommended_ett_size_mm', d.get('ett_size', d.get('ett', '')))
print(ett)
" 2>/dev/null || echo "")
        
        REPORTED_SHAPE=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('trachea_shape', 'unknown'))
" 2>/dev/null || echo "unknown")
        break
    fi
done

REPORT_CREATED_DURING_TASK="${REPORT_CREATED_DURING_TASK:-false}"

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_trachea_gt.json" /tmp/trachea_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/trachea_ground_truth.json 2>/dev/null || true

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
    "measurement_z_mm": "$MEASUREMENT_Z",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_diameter_mm": "$REPORTED_DIAMETER",
    "reported_ett_size_mm": "$REPORTED_ETT",
    "reported_trachea_shape": "$REPORTED_SHAPE",
    "patient_id": "$PATIENT_ID",
    "screenshot_exists": $([ -f "/tmp/tracheal_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/trachea_ground_truth.json" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/tracheal_task_result.json 2>/dev/null || sudo rm -f /tmp/tracheal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tracheal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tracheal_task_result.json
chmod 666 /tmp/tracheal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/tracheal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/tracheal_task_result.json
echo ""
echo "=== Export Complete ==="