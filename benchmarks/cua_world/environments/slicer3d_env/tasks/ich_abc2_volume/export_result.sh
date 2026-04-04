#!/bin/bash
echo "=== Exporting ICH ABC/2 Volume Result ==="

source /workspace/scripts/task_utils.sh

ICH_DIR="/home/ga/Documents/SlicerData/ICH"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENT="$ICH_DIR/agent_measurements.mrk.json"
OUTPUT_REPORT="$ICH_DIR/hemorrhage_report.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/ich_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any measurements from Slicer
    cat > /tmp/export_ich_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/ICH"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Check for line/ruler markups (used for A and B measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length_mm = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        length_cm = length_mm / 10.0
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length_mm,
            "length_cm": length_cm,
            "p1": p1,
            "p2": p2,
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length_mm:.1f} mm ({length_cm:.2f} cm)")

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

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "agent_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run export in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_ich_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_ich_meas" 2>/dev/null || true
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_A_CM=""
MEASURED_B_CM=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$ICH_DIR/measurement.mrk.json"
    "$ICH_DIR/measurements.mrk.json"
    "/home/ga/Documents/agent_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        # Try to extract A and B from measurements
        python3 << PYEOF
import json
try:
    with open("$path") as f:
        data = json.load(f)
    measurements = data.get('measurements', [])
    lengths = []
    for m in measurements:
        if m.get('type') == 'line' and m.get('length_cm', 0) > 0:
            lengths.append(m['length_cm'])
    if len(lengths) >= 2:
        # Assume largest is A, second is B
        lengths.sort(reverse=True)
        print(f"A={lengths[0]:.2f}")
        print(f"B={lengths[1]:.2f}")
    elif len(lengths) == 1:
        print(f"A={lengths[0]:.2f}")
except Exception as e:
    print(f"Error: {e}")
PYEOF
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_A=""
REPORTED_B=""
REPORTED_C=""
REPORTED_VOLUME=""
REPORTED_THRESHOLD=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$ICH_DIR/report.json"
    "$ICH_DIR/ich_report.json"
    "/home/ga/Documents/hemorrhage_report.json"
    "/home/ga/hemorrhage_report.json"
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
        REPORTED_A=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('measurement_A_cm', d.get('A_cm', d.get('a_cm', ''))))" 2>/dev/null || echo "")
        REPORTED_B=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('measurement_B_cm', d.get('B_cm', d.get('b_cm', ''))))" 2>/dev/null || echo "")
        REPORTED_C=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('measurement_C_cm', d.get('C_cm', d.get('c_cm', ''))))" 2>/dev/null || echo "")
        REPORTED_VOLUME=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('calculated_volume_ml', d.get('volume_ml', d.get('volume', ''))))" 2>/dev/null || echo "")
        REPORTED_THRESHOLD=$(python3 -c "import json; d=json.load(open('$path')); v=d.get('exceeds_30ml_threshold', d.get('exceeds_threshold', None)); print('true' if v else 'false' if v is not None else '')" 2>/dev/null || echo "")
        echo "Reported values: A=$REPORTED_A, B=$REPORTED_B, C=$REPORTED_C, Volume=$REPORTED_VOLUME, Threshold=$REPORTED_THRESHOLD"
        break
    fi
done

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/ich_ground_truth.json" /tmp/ich_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/ich_ground_truth.json 2>/dev/null || true

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_measurements.json 2>/dev/null || true
    chmod 644 /tmp/agent_measurements.json 2>/dev/null || true
fi

# Check if files were created/modified during task
MEAS_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
        MEAS_CREATED_DURING_TASK="true"
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

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measurement_created_during_task": $MEAS_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_values": {
        "A_cm": "$REPORTED_A",
        "B_cm": "$REPORTED_B",
        "C_cm": "$REPORTED_C",
        "volume_ml": "$REPORTED_VOLUME",
        "exceeds_threshold": "$REPORTED_THRESHOLD"
    },
    "screenshot_exists": $([ -f "/tmp/ich_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/ich_ground_truth.json" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/ich_task_result.json 2>/dev/null || sudo rm -f /tmp/ich_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ich_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ich_task_result.json
chmod 666 /tmp/ich_task_result.json 2>/dev/null || sudo chmod 666 /tmp/ich_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/ich_task_result.json
echo ""
echo "=== Export Complete ==="