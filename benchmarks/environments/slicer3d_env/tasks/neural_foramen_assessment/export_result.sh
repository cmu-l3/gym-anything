#!/bin/bash
echo "=== Exporting Neural Foramen Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/foramen_measurements.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/foramen_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/foramen_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_foramen_meas.py << 'PYEOF'
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
    meas_path = os.path.join(output_dir, "foramen_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF
    
    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_foramen_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_foramen_meas" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASUREMENT_COUNT=0

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/measurements.mrk.json"
    "$AMOS_DIR/foramen.mrk.json"
    "/home/ga/Documents/foramen_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        MEASUREMENT_COUNT=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(len(data.get('measurements', [])))
" 2>/dev/null || echo "0")
        echo "Found measurements at: $path (count: $MEASUREMENT_COUNT)"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_COMPLETE="false"
REPORT_LEVELS_FOUND=0

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/foramen.json"
    "/home/ga/Documents/foramen_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Check report completeness
        REPORT_LEVELS_FOUND=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
levels = ['L4L5_left', 'L4L5_right', 'L5S1_left', 'L5S1_right']
alt_levels = ['L4-L5_left', 'L4-L5_right', 'L5-S1_left', 'L5-S1_right']
count = 0
for lvl in levels + alt_levels:
    if lvl in data or lvl.lower() in data or lvl.replace('_', '-') in data:
        count += 1
# Cap at 4 since we're checking both formats
print(min(count, 4))
" 2>/dev/null || echo "0")
        
        if [ "$REPORT_LEVELS_FOUND" -ge 4 ]; then
            REPORT_COMPLETE="true"
        fi
        
        echo "Report levels found: $REPORT_LEVELS_FOUND/4"
        break
    fi
done

# Check if files were created during task (anti-gaming)
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

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_foramen_gt.json" /tmp/foramen_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/foramen_ground_truth.json 2>/dev/null || true

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_foramen_meas.json 2>/dev/null || true
    chmod 644 /tmp/agent_foramen_meas.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_foramen_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_foramen_report.json 2>/dev/null || true
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
    "measurement_count": $MEASUREMENT_COUNT,
    "measurement_created_during_task": $MEAS_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_complete": $REPORT_COMPLETE,
    "report_levels_found": $REPORT_LEVELS_FOUND,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "screenshot_exists": $([ -f "/tmp/foramen_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/foramen_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/foramen_task_result.json 2>/dev/null || sudo rm -f /tmp/foramen_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/foramen_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/foramen_task_result.json
chmod 666 /tmp/foramen_task_result.json 2>/dev/null || sudo chmod 666 /tmp/foramen_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/foramen_task_result.json
echo ""
echo "=== Export Complete ==="