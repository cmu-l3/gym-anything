#!/bin/bash
echo "=== Exporting Tumor-to-Ventricle Proximity Result ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_MEASUREMENT="$BRATS_DIR/ventricle_distance.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/proximity_report.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/proximity_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Export any line measurements from Slicer
    cat > /tmp/export_proximity_meas.py << 'PYEOF'
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
            "length_mm": round(length, 2),
            "p1_ras": [round(x, 2) for x in p1],
            "p2_ras": [round(x, 2) for x in p2],
        })
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        
        # Save the markup node
        mrk_path = os.path.join(output_dir, "ventricle_distance.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved to {mrk_path}")

# Also check for any fiducials that might mark points of interest
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        measurements.append({
            "name": node.GetNthControlPointLabel(i),
            "type": "fiducial",
            "position_ras": [round(x, 2) for x in pos],
        })

# Save all measurements
if measurements:
    meas_path = os.path.join(output_dir, "all_measurements.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Exported {len(measurements)} measurement(s)")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_proximity_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_proximity_meas" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASURED_DISTANCE=""
MEASUREMENT_PATH=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$BRATS_DIR/ventricle_distance.mrk.json"
    "$BRATS_DIR/distance.mrk.json"
    "$BRATS_DIR/measurement.mrk.json"
    "/home/ga/Documents/ventricle_distance.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        
        # Check if modified during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            echo "  File was created/modified during task"
        fi
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Extract distance from markup (try multiple formats)
        MEASURED_DISTANCE=$(python3 << PYEOF
import json
import math
try:
    with open("$path") as f:
        data = json.load(f)
    
    # Try to find a line measurement
    # Format 1: Slicer markup JSON
    if 'markups' in data:
        for markup in data.get('markups', []):
            if markup.get('type') == 'Line':
                cps = markup.get('controlPoints', [])
                if len(cps) >= 2:
                    p1 = cps[0].get('position', [0,0,0])
                    p2 = cps[1].get('position', [0,0,0])
                    dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                    print(f"{dist:.2f}")
                    exit(0)
    
    # Format 2: Custom measurements format
    for m in data.get('measurements', []):
        if m.get('type') == 'line' and m.get('length_mm', 0) > 0:
            print(f"{m['length_mm']:.2f}")
            exit(0)
            
except Exception as e:
    pass
print("")
PYEOF
)
        break
    fi
done

echo "Measured distance: $MEASURED_DISTANCE mm"

# Check for report file
REPORT_EXISTS="false"
REPORTED_DISTANCE=""
REPORTED_CLASSIFICATION=""
REPORTED_COMPONENT=""
REPORTED_INVASION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/proximity_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/proximity_report.json"
    "/home/ga/proximity_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_DISTANCE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('minimum_distance_mm', d.get('distance_mm', d.get('distance', ''))))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', ''))" 2>/dev/null || echo "")
        REPORTED_COMPONENT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('nearest_ventricle_component', d.get('ventricle_component', '')))" 2>/dev/null || echo "")
        REPORTED_INVASION=$(python3 -c "import json; d=json.load(open('$path')); print(str(d.get('ventricular_invasion_suspected', d.get('invasion_suspected', ''))).lower())" 2>/dev/null || echo "")
        
        echo "  Reported distance: $REPORTED_DISTANCE mm"
        echo "  Reported classification: $REPORTED_CLASSIFICATION"
        echo "  Reported component: $REPORTED_COMPONENT"
        echo "  Reported invasion: $REPORTED_INVASION"
        break
    fi
done

# Use measured distance if reported is empty
if [ -z "$REPORTED_DISTANCE" ] && [ -n "$MEASURED_DISTANCE" ]; then
    REPORTED_DISTANCE="$MEASURED_DISTANCE"
fi

# Copy ground truth for verifier
if [ -f /tmp/proximity_ground_truth.json ]; then
    chmod 644 /tmp/proximity_ground_truth.json 2>/dev/null || true
fi

# Screenshot exists check
SCREENSHOT_EXISTS="false"
if [ -f /tmp/proximity_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Check for file creation during task
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
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
    "measured_distance_mm": "$MEASURED_DISTANCE",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "reported_distance_mm": "$REPORTED_DISTANCE",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_ventricle_component": "$REPORTED_COMPONENT",
    "reported_invasion_suspected": "$REPORTED_INVASION",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/proximity_task_result.json 2>/dev/null || sudo rm -f /tmp/proximity_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/proximity_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/proximity_task_result.json
chmod 666 /tmp/proximity_task_result.json 2>/dev/null || sudo chmod 666 /tmp/proximity_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

echo ""
echo "Export result:"
cat /tmp/proximity_task_result.json
echo ""
echo "=== Export Complete ==="