#!/bin/bash
echo "=== Exporting Bilateral Kidney Length Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_RIGHT="$AMOS_DIR/right_kidney_length.mrk.json"
OUTPUT_LEFT="$AMOS_DIR/left_kidney_length.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/kidney_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/kidney_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Export any measurements from Slicer scene
    cat > /tmp/export_kidney_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

print("Searching for kidney measurement markups...")

# Find all line/ruler measurements
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

measurements = []
for node in line_nodes:
    name = node.GetName().lower()
    n_points = node.GetNumberOfControlPoints()
    
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        
        # Calculate length in mm
        length_mm = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        length_cm = length_mm / 10.0
        
        measurement = {
            "name": node.GetName(),
            "length_mm": length_mm,
            "length_cm": length_cm,
            "p1": p1,
            "p2": p2
        }
        measurements.append(measurement)
        print(f"  '{node.GetName()}': {length_cm:.2f} cm")
        
        # Try to determine if this is right or left kidney
        if "right" in name or "rk" in name or "r_" in name:
            out_path = os.path.join(output_dir, "right_kidney_length.mrk.json")
            with open(out_path, "w") as f:
                json.dump({"measurement": measurement}, f, indent=2)
            print(f"  Saved as right kidney measurement")
        elif "left" in name or "lk" in name or "l_" in name:
            out_path = os.path.join(output_dir, "left_kidney_length.mrk.json")
            with open(out_path, "w") as f:
                json.dump({"measurement": measurement}, f, indent=2)
            print(f"  Saved as left kidney measurement")

# Save all measurements
if measurements:
    all_meas_path = os.path.join(output_dir, "all_kidney_measurements.json")
    with open(all_meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"All measurements saved to {all_meas_path}")

print("Export complete")
PYEOF

    # Run export script briefly
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_kidney_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 2
fi

# ============================================================
# Check for measurement files
# ============================================================
echo "Checking for measurement files..."

# Right kidney measurement
RIGHT_MEAS_EXISTS="false"
RIGHT_MEAS_LENGTH=""
RIGHT_MEAS_PATH=""

POSSIBLE_RIGHT_PATHS=(
    "$OUTPUT_RIGHT"
    "$AMOS_DIR/right_kidney.mrk.json"
    "$AMOS_DIR/RightKidney.mrk.json"
    "$AMOS_DIR/R_kidney.mrk.json"
)

for path in "${POSSIBLE_RIGHT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        RIGHT_MEAS_EXISTS="true"
        RIGHT_MEAS_PATH="$path"
        echo "Found right kidney measurement: $path"
        
        # Extract length
        RIGHT_MEAS_LENGTH=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurement', data)
length = meas.get('length_cm', meas.get('length_mm', 0) / 10.0)
print(f'{length:.2f}')
" 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_RIGHT" ]; then
            cp "$path" "$OUTPUT_RIGHT" 2>/dev/null || true
        fi
        break
    fi
done

# Left kidney measurement
LEFT_MEAS_EXISTS="false"
LEFT_MEAS_LENGTH=""
LEFT_MEAS_PATH=""

POSSIBLE_LEFT_PATHS=(
    "$OUTPUT_LEFT"
    "$AMOS_DIR/left_kidney.mrk.json"
    "$AMOS_DIR/LeftKidney.mrk.json"
    "$AMOS_DIR/L_kidney.mrk.json"
)

for path in "${POSSIBLE_LEFT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LEFT_MEAS_EXISTS="true"
        LEFT_MEAS_PATH="$path"
        echo "Found left kidney measurement: $path"
        
        LEFT_MEAS_LENGTH=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurement', data)
length = meas.get('length_cm', meas.get('length_mm', 0) / 10.0)
print(f'{length:.2f}')
" 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_LEFT" ]; then
            cp "$path" "$OUTPUT_LEFT" 2>/dev/null || true
        fi
        break
    fi
done

# Try to find measurements from all_kidney_measurements.json if individual not found
if [ "$RIGHT_MEAS_EXISTS" = "false" ] || [ "$LEFT_MEAS_EXISTS" = "false" ]; then
    if [ -f "$AMOS_DIR/all_kidney_measurements.json" ]; then
        echo "Checking all_kidney_measurements.json for missing measurements..."
        python3 << PYEOF
import json
import os

with open("$AMOS_DIR/all_kidney_measurements.json") as f:
    data = json.load(f)

measurements = data.get("measurements", [])
if len(measurements) >= 2:
    # Assume first two are right and left (sorted by x position maybe)
    sorted_meas = sorted(measurements, key=lambda m: m.get("p1", [0])[0], reverse=True)
    
    # Save right (higher x typically)
    if not os.path.exists("$OUTPUT_RIGHT"):
        with open("$OUTPUT_RIGHT", "w") as f:
            json.dump({"measurement": sorted_meas[0]}, f, indent=2)
        print(f"Created right kidney from measurements: {sorted_meas[0].get('length_cm', 0):.2f} cm")
    
    # Save left (lower x typically)
    if not os.path.exists("$OUTPUT_LEFT"):
        with open("$OUTPUT_LEFT", "w") as f:
            json.dump({"measurement": sorted_meas[1]}, f, indent=2)
        print(f"Created left kidney from measurements: {sorted_meas[1].get('length_cm', 0):.2f} cm")
PYEOF
        
        # Re-check
        [ -f "$OUTPUT_RIGHT" ] && RIGHT_MEAS_EXISTS="true"
        [ -f "$OUTPUT_LEFT" ] && LEFT_MEAS_EXISTS="true"
    fi
fi

# ============================================================
# Check for report file
# ============================================================
echo "Checking for report file..."

REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_RIGHT_LENGTH=""
REPORTED_LEFT_LENGTH=""
REPORTED_ASYMMETRY=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/kidney_measurement_report.json"
    "/home/ga/kidney_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report: $path"
        
        # Extract reported values
        REPORTED_RIGHT_LENGTH=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
rk = data.get('right_kidney', {})
print(rk.get('length_cm', rk.get('length', '')))
" 2>/dev/null || echo "")
        
        REPORTED_LEFT_LENGTH=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
lk = data.get('left_kidney', {})
print(lk.get('length_cm', lk.get('length', '')))
" 2>/dev/null || echo "")
        
        REPORTED_ASYMMETRY=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
asym = data.get('asymmetry', {})
print(asym.get('difference_cm', asym.get('difference', '')))
" 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# ============================================================
# Check file timestamps for anti-gaming
# ============================================================
RIGHT_CREATED_DURING_TASK="false"
LEFT_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_RIGHT" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_RIGHT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        RIGHT_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_LEFT" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_LEFT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        LEFT_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_REPORT" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# ============================================================
# Copy ground truth for verifier
# ============================================================
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_kidney_gt.json" /tmp/kidney_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/kidney_ground_truth.json 2>/dev/null || true

# Copy measurement files for verifier
[ -f "$OUTPUT_RIGHT" ] && cp "$OUTPUT_RIGHT" /tmp/right_kidney_measurement.json 2>/dev/null || true
[ -f "$OUTPUT_LEFT" ] && cp "$OUTPUT_LEFT" /tmp/left_kidney_measurement.json 2>/dev/null || true
[ -f "$OUTPUT_REPORT" ] && cp "$OUTPUT_REPORT" /tmp/agent_kidney_report.json 2>/dev/null || true

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "right_kidney": {
        "measurement_exists": $RIGHT_MEAS_EXISTS,
        "measurement_path": "$RIGHT_MEAS_PATH",
        "measured_length_cm": "$RIGHT_MEAS_LENGTH",
        "created_during_task": $RIGHT_CREATED_DURING_TASK
    },
    "left_kidney": {
        "measurement_exists": $LEFT_MEAS_EXISTS,
        "measurement_path": "$LEFT_MEAS_PATH",
        "measured_length_cm": "$LEFT_MEAS_LENGTH",
        "created_during_task": $LEFT_CREATED_DURING_TASK
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "path": "$REPORT_PATH",
        "reported_right_cm": "$REPORTED_RIGHT_LENGTH",
        "reported_left_cm": "$REPORTED_LEFT_LENGTH",
        "reported_asymmetry_cm": "$REPORTED_ASYMMETRY",
        "created_during_task": $REPORT_CREATED_DURING_TASK
    },
    "screenshot_exists": $([ -f "/tmp/kidney_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/kidney_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/kidney_task_result.json 2>/dev/null || sudo rm -f /tmp/kidney_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/kidney_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/kidney_task_result.json
chmod 666 /tmp/kidney_task_result.json 2>/dev/null || sudo chmod 666 /tmp/kidney_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/kidney_task_result.json
echo ""
echo "=== Export Complete ==="