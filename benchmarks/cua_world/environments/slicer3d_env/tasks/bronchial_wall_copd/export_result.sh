#!/bin/bash
echo "=== Exporting Bronchial Wall Assessment Result ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_MEASUREMENT="$LIDC_DIR/bronchial_measurements.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/bronchial_report.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ELAPSED=$((TASK_END - TASK_START))

echo "Task duration: ${ELAPSED} seconds"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/bronchial_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any measurements from Slicer
    cat > /tmp/export_bronchial_meas.py << 'PYEOF'
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
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "z_position": (p1[2] + p2[2]) / 2
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.2f} mm at z={measurement['z_position']:.1f}")

# Also check ruler nodes specifically
ruler_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsRulerNode")
for node in ruler_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        measurement = {
            "name": node.GetName(),
            "type": "ruler",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "z_position": (p1[2] + p2[2]) / 2
        }
        all_measurements.append(measurement)
        print(f"  Ruler '{node.GetName()}': {length:.2f} mm")

# Save measurements if found
if all_measurements:
    meas_path = os.path.join(output_dir, "bronchial_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also save individual markup nodes
    for node in line_nodes:
        try:
            node_path = os.path.join(output_dir, f"{node.GetName().replace(' ', '_')}.mrk.json")
            slicer.util.saveNode(node, node_path)
        except:
            pass
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_bronchial_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_bronchial_meas" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_COUNT=0
MEASUREMENTS_JSON=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$LIDC_DIR/bronchial_measurements.mrk.json"
    "$LIDC_DIR/measurement.mrk.json"
    "$LIDC_DIR/outer_diameter.mrk.json"
    "$LIDC_DIR/inner_diameter.mrk.json"
    "/home/ga/Documents/bronchial_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        echo "Found measurement at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        MEASUREMENT_COUNT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('count', len(d.get('measurements', []))))" 2>/dev/null || echo "0")
        MEASUREMENTS_JSON=$(cat "$path" 2>/dev/null || echo "{}")
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
OUTER_DIAMETER="0"
INNER_DIAMETER="0"
WALL_AREA_PCT="0"
CLASSIFICATION=""
BRONCHUS_LOCATION=""
SLICE_NUMBER="0"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/bronchial_report.json"
    "$LIDC_DIR/report.json"
    "/home/ga/Documents/bronchial_report.json"
    "/home/ga/bronchial_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract values from report
        OUTER_DIAMETER=$(python3 -c "
import json
d = json.load(open('$path'))
v = d.get('outer_diameter_mm', d.get('outer_diameter', d.get('Do', 0)))
print(float(v) if v else 0)
" 2>/dev/null || echo "0")
        
        INNER_DIAMETER=$(python3 -c "
import json
d = json.load(open('$path'))
v = d.get('inner_diameter_mm', d.get('inner_diameter', d.get('Di', 0)))
print(float(v) if v else 0)
" 2>/dev/null || echo "0")
        
        WALL_AREA_PCT=$(python3 -c "
import json
d = json.load(open('$path'))
v = d.get('wall_area_percentage', d.get('wa_percentage', d.get('WA', 0)))
print(float(v) if v else 0)
" 2>/dev/null || echo "0")
        
        CLASSIFICATION=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('classification', d.get('finding', '')))
" 2>/dev/null || echo "")
        
        BRONCHUS_LOCATION=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('bronchus_location', d.get('location', '')))
" 2>/dev/null || echo "")
        
        SLICE_NUMBER=$(python3 -c "
import json
d = json.load(open('$path'))
print(d.get('slice_number', d.get('slice', 0)))
" 2>/dev/null || echo "0")
        
        break
    fi
done

# If no report but measurements exist, try to extract diameters from measurements
if [ "$REPORT_EXISTS" = "false" ] && [ "$MEASUREMENT_EXISTS" = "true" ]; then
    echo "No report found, extracting from measurements..."
    
    # Extract measurements - assume first two lines are outer and inner diameter
    EXTRACTED=$(python3 << 'PYEOF'
import json
import os

meas_path = "/home/ga/Documents/SlicerData/LIDC/bronchial_measurements.mrk.json"
if os.path.exists(meas_path):
    with open(meas_path) as f:
        data = json.load(f)
    measurements = data.get('measurements', [])
    
    # Sort by length (larger is likely outer diameter)
    line_meas = [m for m in measurements if m.get('type') in ['line', 'ruler']]
    line_meas.sort(key=lambda x: x.get('length_mm', 0), reverse=True)
    
    if len(line_meas) >= 2:
        outer = line_meas[0].get('length_mm', 0)
        inner = line_meas[1].get('length_mm', 0)
        print(f"{outer:.2f},{inner:.2f}")
    elif len(line_meas) == 1:
        print(f"{line_meas[0].get('length_mm', 0):.2f},0")
    else:
        print("0,0")
else:
    print("0,0")
PYEOF
)
    
    if [ -n "$EXTRACTED" ] && [ "$EXTRACTED" != "0,0" ]; then
        OUTER_DIAMETER=$(echo "$EXTRACTED" | cut -d',' -f1)
        INNER_DIAMETER=$(echo "$EXTRACTED" | cut -d',' -f2)
        echo "Extracted from measurements: outer=$OUTER_DIAMETER, inner=$INNER_DIAMETER"
    fi
fi

# Calculate expected WA% from diameters for verification
EXPECTED_WA_PCT="0"
if [ "$OUTER_DIAMETER" != "0" ] && [ "$INNER_DIAMETER" != "0" ]; then
    EXPECTED_WA_PCT=$(python3 -c "
do = float('$OUTER_DIAMETER')
di = float('$INNER_DIAMETER')
if do > 0 and di < do:
    wa = ((do**2 - di**2) / do**2) * 100
    print(f'{wa:.2f}')
else:
    print('0')
" 2>/dev/null || echo "0")
fi

# Check for any screenshots taken during task
SCREENSHOT_COUNT=$(find "$LIDC_DIR" /home/ga/Documents -name "*.png" -newer /tmp/task_start_timestamp.txt 2>/dev/null | wc -l)

# Get file modification times for anti-gaming
MEAS_MTIME="0"
REPORT_MTIME="0"
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
fi
if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
fi

# Check if files were created during task
MEAS_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"
if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
    MEAS_CREATED_DURING_TASK="true"
fi
if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measurement_count": $MEASUREMENT_COUNT,
    "measurement_created_during_task": $MEAS_CREATED_DURING_TASK,
    "report_file_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "outer_diameter_mm": $OUTER_DIAMETER,
    "inner_diameter_mm": $INNER_DIAMETER,
    "wall_area_percentage_reported": $WALL_AREA_PCT,
    "wall_area_percentage_expected": $EXPECTED_WA_PCT,
    "classification": "$CLASSIFICATION",
    "bronchus_location": "$BRONCHUS_LOCATION",
    "slice_number": $SLICE_NUMBER,
    "screenshot_count": $SCREENSHOT_COUNT,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "elapsed_seconds": $ELAPSED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/bronchial_task_result.json 2>/dev/null || sudo rm -f /tmp/bronchial_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bronchial_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/bronchial_task_result.json
chmod 666 /tmp/bronchial_task_result.json 2>/dev/null || sudo chmod 666 /tmp/bronchial_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy final screenshot for verification
if [ -f /tmp/bronchial_final.png ]; then
    cp /tmp/bronchial_final.png "$LIDC_DIR/final_screenshot.png" 2>/dev/null || true
fi

echo ""
echo "=== Export Result ==="
cat /tmp/bronchial_task_result.json
echo ""
echo "=== Export Complete ==="