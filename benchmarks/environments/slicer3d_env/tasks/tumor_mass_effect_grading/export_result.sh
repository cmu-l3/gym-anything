#!/bin/bash
echo "=== Exporting Brain Tumor Mass Effect Grading Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENTS="$BRATS_DIR/mass_effect_measurements.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/mass_effect_report.json"
SCREENSHOTS_DIR="$BRATS_DIR/screenshots"

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/mass_effect_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any measurements from Slicer
    cat > /tmp/export_mass_effect_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
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
        print(f"  Line '{node.GetName()}': {length:.2f} mm")

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
    meas_path = os.path.join(output_dir, "mass_effect_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements")
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_mass_effect_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_mass_effect_meas" 2>/dev/null || true
fi

# Check for agent's measurement file
MEASUREMENTS_EXISTS="false"
MEASUREMENTS_PATH=""
MEASUREMENT_COUNT=0

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENTS"
    "$BRATS_DIR/measurements.mrk.json"
    "$BRATS_DIR/midline_measurement.mrk.json"
    "/home/ga/Documents/mass_effect_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENTS_EXISTS="true"
        MEASUREMENTS_PATH="$path"
        echo "Found measurements at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENTS" ]; then
            cp "$path" "$OUTPUT_MEASUREMENTS" 2>/dev/null || true
        fi
        MEASUREMENT_COUNT=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurements', [])
print(len(meas))
" 2>/dev/null || echo "0")
        break
    fi
done

# Check for agent's report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_MIDLINE_SHIFT=""
REPORTED_VENT_RATIO=""
REPORTED_SUBFALCINE=""
REPORTED_SULCAL=""
REPORTED_UNCAL=""
REPORTED_GRADE=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/mass_effect.json"
    "/home/ga/Documents/mass_effect_report.json"
    "/home/ga/mass_effect_report.json"
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
        REPORTED_MIDLINE_SHIFT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('midline_shift_mm', ''))" 2>/dev/null || echo "")
        REPORTED_VENT_RATIO=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('ventricular_ratio', ''))" 2>/dev/null || echo "")
        REPORTED_SUBFALCINE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('subfalcine_herniation', ''))" 2>/dev/null || echo "")
        REPORTED_SULCAL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('sulcal_effacement_score', ''))" 2>/dev/null || echo "")
        REPORTED_UNCAL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('uncal_herniation', ''))" 2>/dev/null || echo "")
        REPORTED_GRADE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('overall_grade', ''))" 2>/dev/null || echo "")
        
        echo "Extracted values:"
        echo "  Midline shift: $REPORTED_MIDLINE_SHIFT"
        echo "  Ventricular ratio: $REPORTED_VENT_RATIO"
        echo "  Subfalcine: $REPORTED_SUBFALCINE"
        echo "  Sulcal effacement: $REPORTED_SULCAL"
        echo "  Uncal: $REPORTED_UNCAL"
        echo "  Grade: $REPORTED_GRADE"
        break
    fi
done

# Check for screenshots
SCREENSHOTS_COUNT=0
SCREENSHOTS_CREATED="false"

if [ -d "$SCREENSHOTS_DIR" ]; then
    SCREENSHOTS_COUNT=$(find "$SCREENSHOTS_DIR" -name "*.png" -type f 2>/dev/null | wc -l)
fi

# Also check for screenshots created after task start
NEW_SCREENSHOTS=$(find "$BRATS_DIR" /home/ga/Documents -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

if [ "$SCREENSHOTS_COUNT" -gt 0 ] || [ "$NEW_SCREENSHOTS" -gt 0 ]; then
    SCREENSHOTS_CREATED="true"
    SCREENSHOTS_COUNT=$((SCREENSHOTS_COUNT + NEW_SCREENSHOTS))
fi

echo "Screenshots found: $SCREENSHOTS_COUNT"

# Check if files were created during task
MEAS_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_MEASUREMENTS" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENTS" 2>/dev/null || echo "0")
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

# Copy ground truth for verifier
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_mass_effect_gt.json" /tmp/mass_effect_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/mass_effect_ground_truth.json 2>/dev/null || true

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_mass_effect_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_mass_effect_report.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_MEASUREMENTS" ]; then
    cp "$OUTPUT_MEASUREMENTS" /tmp/agent_mass_effect_measurements.json 2>/dev/null || true
    chmod 644 /tmp/agent_mass_effect_measurements.json 2>/dev/null || true
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
    "measurements_exists": $MEASUREMENTS_EXISTS,
    "measurements_path": "$MEASUREMENTS_PATH",
    "measurement_count": $MEASUREMENT_COUNT,
    "measurements_created_during_task": $MEAS_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_midline_shift_mm": "$REPORTED_MIDLINE_SHIFT",
    "reported_ventricular_ratio": "$REPORTED_VENT_RATIO",
    "reported_subfalcine_herniation": "$REPORTED_SUBFALCINE",
    "reported_sulcal_effacement": "$REPORTED_SULCAL",
    "reported_uncal_herniation": "$REPORTED_UNCAL",
    "reported_grade": "$REPORTED_GRADE",
    "screenshots_created": $SCREENSHOTS_CREATED,
    "screenshots_count": $SCREENSHOTS_COUNT,
    "screenshot_exists": $([ -f "/tmp/mass_effect_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/mass_effect_ground_truth.json" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/mass_effect_task_result.json 2>/dev/null || sudo rm -f /tmp/mass_effect_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mass_effect_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/mass_effect_task_result.json
chmod 666 /tmp/mass_effect_task_result.json 2>/dev/null || sudo chmod 666 /tmp/mass_effect_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/mass_effect_task_result.json
echo ""
echo "=== Export Complete ==="