#!/bin/bash
echo "=== Exporting Fat Thickness Measurement Result ==="

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
OUTPUT_MEASUREMENT="$AMOS_DIR/fat_thickness_measurement.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/surgical_planning_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot FIRST
echo "Capturing final screenshot..."
take_screenshot /tmp/fat_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to export any markups from Slicer
    cat > /tmp/export_fat_markups.py << 'PYEOF'
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
            "length_mm": round(length, 2),
            "p1": p1,
            "p2": p2,
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        
        # Save the node directly
        mrk_path = os.path.join(output_dir, "fat_thickness_measurement.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved markup to {mrk_path}")

# Also check for ruler annotations (older format)
ruler_nodes = slicer.util.getNodesByClass("vtkMRMLAnnotationRulerNode")
print(f"Found {len(ruler_nodes)} annotation ruler(s)")

for node in ruler_nodes:
    p1 = [0.0, 0.0, 0.0]
    p2 = [0.0, 0.0, 0.0]
    node.GetPosition1(p1)
    node.GetPosition2(p2)
    length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
    if length > 0:
        measurement = {
            "name": node.GetName(),
            "type": "ruler",
            "length_mm": round(length, 2),
            "p1": p1,
            "p2": p2,
        }
        all_measurements.append(measurement)
        print(f"  Ruler '{node.GetName()}': {length:.2f} mm")

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "fat_thickness_measurement.mrk.json")
    if not os.path.exists(meas_path):
        with open(meas_path, "w") as f:
            json.dump({"measurements": all_measurements}, f, indent=2)
        print(f"Exported {len(all_measurements)} measurements")
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_fat_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_fat_markups" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_VALUE=""
MEASUREMENT_CREATED_DURING_TASK="false"

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/measurement.mrk.json"
    "$AMOS_DIR/ruler.mrk.json"
    "$AMOS_DIR/L.mrk.json"
    "/home/ga/Documents/fat_thickness_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        
        # Check if file was created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            MEASUREMENT_CREATED_DURING_TASK="true"
            echo "  File created during task (mtime: $FILE_MTIME > start: $TASK_START)"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Extract measurement value
        MEASURED_VALUE=$(python3 << PYEOF
import json
import math
try:
    with open('$path') as f:
        data = json.load(f)
    
    # Try different JSON structures
    # Structure 1: Slicer markup format with controlPoints
    if 'markups' in data:
        for markup in data.get('markups', []):
            cps = markup.get('controlPoints', [])
            if len(cps) >= 2:
                p1 = cps[0].get('position', [0,0,0])
                p2 = cps[1].get('position', [0,0,0])
                length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                if length > 0:
                    print(f"{length:.2f}")
                    exit()
            # Also check measurements array
            for m in markup.get('measurements', []):
                if 'length' in m.get('name', '').lower() or m.get('name') == 'length':
                    print(f"{m.get('value', 0):.2f}")
                    exit()
    
    # Structure 2: Custom format with measurements array
    for m in data.get('measurements', []):
        if m.get('type') in ['line', 'ruler'] and m.get('length_mm', 0) > 0:
            print(f"{m['length_mm']:.2f}")
            exit()
    
    print("0")
except Exception as e:
    print("0")
PYEOF
)
        echo "  Measured value: $MEASURED_VALUE mm"
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_THICKNESS=""
REPORTED_CATEGORY=""
REPORTED_LEVEL=""
REPORT_CREATED_DURING_TASK="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/fat_report.json"
    "/home/ga/Documents/surgical_planning_report.json"
    "/home/ga/surgical_planning_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Check if file was created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
            echo "  File created during task"
        fi
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        eval $(python3 << PYEOF
import json
try:
    with open('$path') as f:
        data = json.load(f)
    
    # Try various field names for thickness
    thickness = data.get('fat_thickness_mm', 
                data.get('thickness_mm', 
                data.get('measurement_mm',
                data.get('thickness',
                data.get('fat_thickness', 0)))))
    
    # Try various field names for category
    category = data.get('surgical_category',
               data.get('category',
               data.get('risk_category',
               data.get('classification', ''))))
    
    # Try various field names for level
    level = data.get('vertebral_level',
            data.get('level',
            data.get('anatomical_level',
            data.get('vertebra', ''))))
    
    print(f'REPORTED_THICKNESS="{thickness}"')
    print(f'REPORTED_CATEGORY="{category}"')
    print(f'REPORTED_LEVEL="{level}"')
except Exception as e:
    print('REPORTED_THICKNESS=""')
    print('REPORTED_CATEGORY=""')
    print('REPORTED_LEVEL=""')
PYEOF
)
        echo "  Reported: thickness=$REPORTED_THICKNESS, category=$REPORTED_CATEGORY, level=$REPORTED_LEVEL"
        break
    fi
done

# Copy ground truth for verification
echo "Copying ground truth for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_fat_gt.json" /tmp/fat_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/fat_ground_truth.json 2>/dev/null || true

# Check screenshot
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/fat_final.png" ]; then
    SCREENSHOT_EXISTS="true"
    SIZE=$(stat -c %s /tmp/fat_final.png 2>/dev/null || echo "0")
    echo "Final screenshot: ${SIZE} bytes"
fi

# Create result JSON
echo "Creating result JSON..."
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measurement_file_path": "$MEASUREMENT_PATH",
    "measurement_created_during_task": $MEASUREMENT_CREATED_DURING_TASK,
    "measurement_mm": "$MEASURED_VALUE",
    "report_file_exists": $REPORT_EXISTS,
    "report_file_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_thickness_mm": "$REPORTED_THICKNESS",
    "report_category": "$REPORTED_CATEGORY",
    "report_vertebral_level": "$REPORTED_LEVEL",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permission handling
rm -f /tmp/fat_task_result.json 2>/dev/null || sudo rm -f /tmp/fat_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fat_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fat_task_result.json
chmod 666 /tmp/fat_task_result.json 2>/dev/null || sudo chmod 666 /tmp/fat_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/fat_task_result.json
echo ""
echo "=== Export Complete ==="