#!/bin/bash
echo "=== Exporting Brain Midline Shift Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_MEASUREMENT="$BRATS_DIR/midline_measurement.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/midline_shift_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/midline_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any line markups from Slicer
    cat > /tmp/export_midline_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

measurements = []

# Check for line/ruler markups
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
        measurements.append({
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "midpoint_z": (p1[2] + p2[2]) / 2.0
        })
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        
        # Save the markup node
        mrk_path = os.path.join(output_dir, "midline_measurement.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved to {mrk_path}")

# Save measurements summary
if measurements:
    summary_path = os.path.join(output_dir, "measurements_summary.json")
    with open(summary_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Summary saved to {summary_path}")

print("Export complete")
PYEOF

    # Run export in background
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_midline_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_midline_meas" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_SHIFT_MM=""
MEASUREMENT_MTIME="0"

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$BRATS_DIR/midline_measurement.mrk.json"
    "$BRATS_DIR/measurement.mrk.json"
    "$BRATS_DIR/ruler.mrk.json"
    "$BRATS_DIR/line.mrk.json"
    "/home/ga/Documents/midline_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        MEASUREMENT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found measurement at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Extract measurement length
        MEASURED_SHIFT_MM=$(python3 << PYEOF
import json
import math
try:
    with open("$path", "r") as f:
        data = json.load(f)
    
    # Try different markup formats
    length = None
    
    # Format 1: Direct measurements array
    if "measurements" in data:
        for m in data["measurements"]:
            if m.get("type") == "line" and m.get("length_mm", 0) > 0:
                length = m["length_mm"]
                break
    
    # Format 2: Slicer markup format with controlPoints
    if length is None and "markups" in data:
        for markup in data["markups"]:
            if markup.get("type") == "Line":
                cps = markup.get("controlPoints", [])
                if len(cps) >= 2:
                    p1 = cps[0].get("position", [0,0,0])
                    p2 = cps[1].get("position", [0,0,0])
                    length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                    break
    
    # Format 3: Direct controlPoints
    if length is None and "controlPoints" in data:
        cps = data["controlPoints"]
        if len(cps) >= 2:
            p1 = cps[0].get("position", [0,0,0])
            p2 = cps[1].get("position", [0,0,0])
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
    
    if length is not None:
        print(f"{length:.2f}")
    else:
        print("")
except Exception as e:
    print("")
PYEOF
)
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_SHIFT_MM=""
REPORTED_DIRECTION=""
REPORTED_SEVERITY=""
REPORT_MTIME="0"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/midline_shift_report.json"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/midline_report.json"
    "/home/ga/Documents/midline_shift_report.json"
    "/home/ga/midline_shift_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found report at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_SHIFT_MM=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('shift_mm', d.get('diameter_mm', d.get('measurement_mm', ''))))" 2>/dev/null || echo "")
        REPORTED_DIRECTION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('direction', ''))" 2>/dev/null || echo "")
        REPORTED_SEVERITY=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('severity', d.get('classification', '')))" 2>/dev/null || echo "")
        
        echo "Report contents:"
        echo "  shift_mm: $REPORTED_SHIFT_MM"
        echo "  direction: $REPORTED_DIRECTION"
        echo "  severity: $REPORTED_SEVERITY"
        break
    fi
done

# Check if files were created during task (anti-gaming)
MEASUREMENT_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ "$MEASUREMENT_MTIME" -gt "$TASK_START" ]; then
    MEASUREMENT_CREATED_DURING_TASK="true"
fi

if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# Load ground truth
GT_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_midline_gt.json"
GT_SHIFT_MM=""
GT_DIRECTION=""
GT_SEVERITY=""

if [ -f "$GT_FILE" ]; then
    GT_SHIFT_MM=$(python3 -c "import json; d=json.load(open('$GT_FILE')); print(d.get('shift_mm', ''))" 2>/dev/null || echo "")
    GT_DIRECTION=$(python3 -c "import json; d=json.load(open('$GT_FILE')); print(d.get('direction', ''))" 2>/dev/null || echo "")
    GT_SEVERITY=$(python3 -c "import json; d=json.load(open('$GT_FILE')); print(d.get('severity', ''))" 2>/dev/null || echo "")
fi

# Copy ground truth for verifier
cp "$GT_FILE" /tmp/midline_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/midline_ground_truth.json 2>/dev/null || true

# Check for summary file (alternative measurement source)
if [ -z "$MEASURED_SHIFT_MM" ] && [ -f "$BRATS_DIR/measurements_summary.json" ]; then
    MEASURED_SHIFT_MM=$(python3 -c "
import json
with open('$BRATS_DIR/measurements_summary.json') as f:
    d = json.load(f)
for m in d.get('measurements', []):
    if m.get('length_mm', 0) > 0:
        print(f\"{m['length_mm']:.2f}\")
        break
" 2>/dev/null || echo "")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sample_id": "$SAMPLE_ID",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measurement_created_during_task": $MEASUREMENT_CREATED_DURING_TASK,
    "measured_shift_mm": "$MEASURED_SHIFT_MM",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_shift_mm": "$REPORTED_SHIFT_MM",
    "reported_direction": "$REPORTED_DIRECTION",
    "reported_severity": "$REPORTED_SEVERITY",
    "ground_truth_shift_mm": "$GT_SHIFT_MM",
    "ground_truth_direction": "$GT_DIRECTION",
    "ground_truth_severity": "$GT_SEVERITY",
    "screenshot_exists": $([ -f "/tmp/midline_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/midline_task_result.json 2>/dev/null || sudo rm -f /tmp/midline_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/midline_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/midline_task_result.json
chmod 666 /tmp/midline_task_result.json 2>/dev/null || sudo chmod 666 /tmp/midline_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/midline_task_result.json
echo ""
echo "=== Export Complete ==="