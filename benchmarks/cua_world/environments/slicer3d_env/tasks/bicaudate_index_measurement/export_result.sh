#!/bin/bash
echo "=== Exporting Bicaudate Index Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_IC="$BRATS_DIR/intercaudate_measurement.mrk.json"
OUTPUT_BW="$BRATS_DIR/brain_width_measurement.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/bicaudate_report.json"

# Get task start time for timestamp verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/bicaudate_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer before analysis
    cat > /tmp/export_bicaudate_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Find all line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

measurements = []
for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
        
        # Determine z-coordinate (slice level)
        avg_z = (p1[2] + p2[2]) / 2
        
        meas = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2],
            "slice_z": round(avg_z, 2)
        }
        measurements.append(meas)
        print(f"  Line '{node.GetName()}': {length:.2f} mm at z={avg_z:.1f}")
        
        # Save individual measurement files
        node_name_lower = node.GetName().lower()
        if "intercaudate" in node_name_lower or "ic" in node_name_lower:
            ic_path = os.path.join(output_dir, "intercaudate_measurement.mrk.json")
            with open(ic_path, "w") as f:
                json.dump({"measurement": meas}, f, indent=2)
            print(f"  Saved intercaudate to {ic_path}")
        elif "brain" in node_name_lower or "width" in node_name_lower or "bw" in node_name_lower:
            bw_path = os.path.join(output_dir, "brain_width_measurement.mrk.json")
            with open(bw_path, "w") as f:
                json.dump({"measurement": meas}, f, indent=2)
            print(f"  Saved brain width to {bw_path}")

# If we have exactly 2 measurements, try to identify them by length
if len(measurements) == 2 and not os.path.exists(os.path.join(output_dir, "intercaudate_measurement.mrk.json")):
    # Shorter one is likely intercaudate, longer is brain width
    sorted_meas = sorted(measurements, key=lambda x: x["length_mm"])
    
    ic_path = os.path.join(output_dir, "intercaudate_measurement.mrk.json")
    with open(ic_path, "w") as f:
        json.dump({"measurement": sorted_meas[0]}, f, indent=2)
    print(f"  Auto-saved shorter measurement as intercaudate: {sorted_meas[0]['length_mm']:.2f} mm")
    
    bw_path = os.path.join(output_dir, "brain_width_measurement.mrk.json")
    with open(bw_path, "w") as f:
        json.dump({"measurement": sorted_meas[1]}, f, indent=2)
    print(f"  Auto-saved longer measurement as brain width: {sorted_meas[1]['length_mm']:.2f} mm")

# Save all measurements
all_meas_path = os.path.join(output_dir, "all_measurements.json")
with open(all_meas_path, "w") as f:
    json.dump({"measurements": measurements}, f, indent=2)

print(f"Exported {len(measurements)} measurements")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_bicaudate_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_bicaudate_meas" 2>/dev/null || true
fi

# Check for intercaudate measurement
IC_EXISTS="false"
IC_VALUE=""
IC_MTIME="0"

POSSIBLE_IC_PATHS=(
    "$OUTPUT_IC"
    "$BRATS_DIR/IC.mrk.json"
    "$BRATS_DIR/intercaudate.mrk.json"
)

for path in "${POSSIBLE_IC_PATHS[@]}"; do
    if [ -f "$path" ]; then
        IC_EXISTS="true"
        IC_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        IC_VALUE=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurement', data)
print(meas.get('length_mm', ''))
" 2>/dev/null || echo "")
        if [ "$path" != "$OUTPUT_IC" ]; then
            cp "$path" "$OUTPUT_IC" 2>/dev/null || true
        fi
        echo "Found intercaudate measurement: $IC_VALUE mm"
        break
    fi
done

# Check for brain width measurement
BW_EXISTS="false"
BW_VALUE=""
BW_MTIME="0"

POSSIBLE_BW_PATHS=(
    "$OUTPUT_BW"
    "$BRATS_DIR/BW.mrk.json"
    "$BRATS_DIR/brain_width.mrk.json"
)

for path in "${POSSIBLE_BW_PATHS[@]}"; do
    if [ -f "$path" ]; then
        BW_EXISTS="true"
        BW_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        BW_VALUE=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurement', data)
print(meas.get('length_mm', ''))
" 2>/dev/null || echo "")
        if [ "$path" != "$OUTPUT_BW" ]; then
            cp "$path" "$OUTPUT_BW" 2>/dev/null || true
        fi
        echo "Found brain width measurement: $BW_VALUE mm"
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORTED_IC=""
REPORTED_BW=""
REPORTED_BCI=""
REPORTED_CLASS=""
REPORTED_SLICE=""
REPORT_MTIME="0"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/bicaudate_report.json"
    "/home/ga/bicaudate_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        REPORTED_IC=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('intercaudate_distance_mm', ''))" 2>/dev/null || echo "")
        REPORTED_BW=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('brain_width_mm', ''))" 2>/dev/null || echo "")
        REPORTED_BCI=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('bicaudate_index', ''))" 2>/dev/null || echo "")
        REPORTED_CLASS=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', ''))" 2>/dev/null || echo "")
        REPORTED_SLICE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('slice_number', ''))" 2>/dev/null || echo "")
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        echo "Found report file"
        break
    fi
done

# Check if files were created during the task (anti-gaming)
IC_CREATED_DURING_TASK="false"
BW_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ "$IC_EXISTS" = "true" ] && [ "$IC_MTIME" -gt "$TASK_START" ]; then
    IC_CREATED_DURING_TASK="true"
fi

if [ "$BW_EXISTS" = "true" ] && [ "$BW_MTIME" -gt "$TASK_START" ]; then
    BW_CREATED_DURING_TASK="true"
fi

if [ "$REPORT_EXISTS" = "true" ] && [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_bicaudate_gt.json" /tmp/bicaudate_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/bicaudate_ground_truth.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "ic_measurement_exists": $IC_EXISTS,
    "ic_measurement_mm": "$IC_VALUE",
    "ic_created_during_task": $IC_CREATED_DURING_TASK,
    "bw_measurement_exists": $BW_EXISTS,
    "bw_measurement_mm": "$BW_VALUE",
    "bw_created_during_task": $BW_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_intercaudate_mm": "$REPORTED_IC",
    "reported_brain_width_mm": "$REPORTED_BW",
    "reported_bicaudate_index": "$REPORTED_BCI",
    "reported_classification": "$REPORTED_CLASS",
    "reported_slice": "$REPORTED_SLICE",
    "screenshot_exists": $([ -f "/tmp/bicaudate_final.png" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/bicaudate_task_result.json 2>/dev/null || sudo rm -f /tmp/bicaudate_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bicaudate_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/bicaudate_task_result.json
chmod 666 /tmp/bicaudate_task_result.json 2>/dev/null || sudo chmod 666 /tmp/bicaudate_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/bicaudate_task_result.json
echo ""
echo "=== Export Complete ==="