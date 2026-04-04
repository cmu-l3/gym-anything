#!/bin/bash
echo "=== Exporting Gallbladder Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/gallbladder_case_id.txt ]; then
    CASE_ID=$(cat /tmp/gallbladder_case_id.txt)
else
    CASE_ID="amos_gb_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/gallbladder_measurements.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/gallbladder_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/gallbladder_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer before closing
    cat > /tmp/export_gb_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
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
            "length_mm": length,
            "p1": p1,
            "p2": p2,
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
            "position": pos,
        })

# Save measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "gallbladder_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "exported_from_slicer": True}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_gb_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_gb_meas" 2>/dev/null || true
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASUREMENT_COUNT=0

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/measurements.mrk.json"
    "$AMOS_DIR/gb_measurement.mrk.json"
    "/home/ga/Documents/gallbladder_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        MEASUREMENT_COUNT=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurements', [])
print(len([m for m in meas if m.get('type') == 'line']))
" 2>/dev/null || echo "0")
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_LENGTH=""
REPORTED_TRANSVERSE=""
REPORTED_WALL=""
REPORTED_CLASSIFICATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/gb_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/gallbladder_report.json"
    "/home/ga/gallbladder_report.json"
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
        REPORTED_LENGTH=$(python3 -c "
import json
d = json.load(open('$path'))
m = d.get('measurements', {})
v = m.get('length_cm', m.get('length', ''))
print(v)
" 2>/dev/null || echo "")
        
        REPORTED_TRANSVERSE=$(python3 -c "
import json
d = json.load(open('$path'))
m = d.get('measurements', {})
v = m.get('transverse_diameter_cm', m.get('transverse_cm', m.get('transverse', '')))
print(v)
" 2>/dev/null || echo "")
        
        REPORTED_WALL=$(python3 -c "
import json
d = json.load(open('$path'))
m = d.get('measurements', {})
v = m.get('wall_thickness_mm', m.get('wall_mm', m.get('wall', '')))
print(v)
" 2>/dev/null || echo "")
        
        REPORTED_CLASSIFICATION=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('classification', ''))
" 2>/dev/null || echo "")
        
        break
    fi
done

# Check file modification times for anti-gaming
MEASUREMENT_MODIFIED_DURING_TASK="false"
REPORT_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
        MEASUREMENT_MODIFIED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED_DURING_TASK="true"
    fi
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer
sleep 2

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_gb_gt.json" /tmp/gallbladder_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/gallbladder_ground_truth.json 2>/dev/null || true

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_gb_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_gb_report.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_gb_measurements.json 2>/dev/null || true
    chmod 644 /tmp/agent_gb_measurements.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measurement_count": $MEASUREMENT_COUNT,
    "measurement_modified_during_task": $MEASUREMENT_MODIFIED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_modified_during_task": $REPORT_MODIFIED_DURING_TASK,
    "reported_length_cm": "$REPORTED_LENGTH",
    "reported_transverse_cm": "$REPORTED_TRANSVERSE",
    "reported_wall_mm": "$REPORTED_WALL",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "screenshot_exists": $([ -f "/tmp/gallbladder_final.png" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/gallbladder_task_result.json 2>/dev/null || sudo rm -f /tmp/gallbladder_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/gallbladder_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/gallbladder_task_result.json
chmod 666 /tmp/gallbladder_task_result.json 2>/dev/null || sudo chmod 666 /tmp/gallbladder_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/gallbladder_task_result.json
echo ""
echo "=== Export Complete ==="