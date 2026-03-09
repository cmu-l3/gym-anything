#!/bin/bash
echo "=== Exporting Aortic Path Length Task Results ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_CURVE="$AMOS_DIR/aortic_curve.mrk.json"
OUTPUT_STRAIGHT="$AMOS_DIR/aortic_straight.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/evar_measurements.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export markups from Slicer before checking files
    cat > /tmp/export_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

print("Exporting markups from Slicer scene...")

# Export open curves
curve_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsCurveNode")
print(f"Found {len(curve_nodes)} curve node(s)")

for node in curve_nodes:
    curve_path = os.path.join(output_dir, "aortic_curve.mrk.json")
    success = slicer.util.saveNode(node, curve_path)
    if success:
        print(f"  Saved curve '{node.GetName()}' to {curve_path}")
        # Get curve length
        n_points = node.GetNumberOfControlPoints()
        if hasattr(node, 'GetCurveLengthWorld'):
            length = node.GetCurveLengthWorld()
            print(f"  Curve length: {length:.2f} mm, Control points: {n_points}")
    break  # Only save first curve

# Export line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line node(s)")

for node in line_nodes:
    line_path = os.path.join(output_dir, "aortic_straight.mrk.json")
    success = slicer.util.saveNode(node, line_path)
    if success:
        print(f"  Saved line '{node.GetName()}' to {line_path}")
        # Get line length
        n_points = node.GetNumberOfControlPoints()
        if n_points >= 2:
            p1 = [0.0, 0.0, 0.0]
            p2 = [0.0, 0.0, 0.0]
            node.GetNthControlPointPosition(0, p1)
            node.GetNthControlPointPosition(1, p2)
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            print(f"  Line length: {length:.2f} mm")
    break  # Only save first line

print("Markup export complete")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_markups" 2>/dev/null || true
fi

# Check for curve file
CURVE_EXISTS="false"
CURVE_PATH=""
CURVE_MTIME="0"
CURVE_VALID="false"
CURVE_LENGTH=""
CURVE_POINTS="0"

POSSIBLE_CURVE_PATHS=(
    "$OUTPUT_CURVE"
    "$AMOS_DIR/Curve.mrk.json"
    "$AMOS_DIR/curve.mrk.json"
    "$AMOS_DIR/OpenCurve.mrk.json"
    "/home/ga/Documents/aortic_curve.mrk.json"
)

for path in "${POSSIBLE_CURVE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CURVE_EXISTS="true"
        CURVE_PATH="$path"
        CURVE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$CURVE_MTIME" -gt "$TASK_START" ]; then
            CURVE_VALID="true"
        fi
        
        echo "Found curve at: $path (mtime: $CURVE_MTIME, valid: $CURVE_VALID)"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_CURVE" ]; then
            cp "$path" "$OUTPUT_CURVE" 2>/dev/null || true
        fi
        
        # Extract curve info
        CURVE_INFO=$(python3 -c "
import json
import math
try:
    with open('$path') as f:
        data = json.load(f)
    markups = data.get('markups', [])
    if markups:
        m = markups[0]
        points = m.get('controlPoints', [])
        num_points = len(points)
        
        # Get length from measurements if available
        length = 0
        for meas in m.get('measurements', []):
            if 'length' in meas.get('name', '').lower():
                length = meas.get('value', 0)
                break
        
        # If no measurement, compute from points
        if length == 0 and num_points >= 2:
            total = 0
            for i in range(1, num_points):
                p1 = points[i-1].get('position', [0,0,0])
                p2 = points[i].get('position', [0,0,0])
                dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                total += dist
            length = total
        
        print(f'{num_points},{length:.2f}')
except Exception as e:
    print(f'0,0')
" 2>/dev/null || echo "0,0")
        
        CURVE_POINTS=$(echo "$CURVE_INFO" | cut -d',' -f1)
        CURVE_LENGTH=$(echo "$CURVE_INFO" | cut -d',' -f2)
        echo "  Curve points: $CURVE_POINTS, length: $CURVE_LENGTH mm"
        break
    fi
done

# Check for straight line file
STRAIGHT_EXISTS="false"
STRAIGHT_PATH=""
STRAIGHT_MTIME="0"
STRAIGHT_VALID="false"
STRAIGHT_LENGTH=""

POSSIBLE_STRAIGHT_PATHS=(
    "$OUTPUT_STRAIGHT"
    "$AMOS_DIR/Line.mrk.json"
    "$AMOS_DIR/line.mrk.json"
    "$AMOS_DIR/Ruler.mrk.json"
    "/home/ga/Documents/aortic_straight.mrk.json"
)

for path in "${POSSIBLE_STRAIGHT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        STRAIGHT_EXISTS="true"
        STRAIGHT_PATH="$path"
        STRAIGHT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$STRAIGHT_MTIME" -gt "$TASK_START" ]; then
            STRAIGHT_VALID="true"
        fi
        
        echo "Found straight line at: $path (valid: $STRAIGHT_VALID)"
        
        if [ "$path" != "$OUTPUT_STRAIGHT" ]; then
            cp "$path" "$OUTPUT_STRAIGHT" 2>/dev/null || true
        fi
        
        # Extract line length
        STRAIGHT_LENGTH=$(python3 -c "
import json
import math
try:
    with open('$path') as f:
        data = json.load(f)
    markups = data.get('markups', [])
    if markups:
        m = markups[0]
        points = m.get('controlPoints', [])
        if len(points) >= 2:
            p1 = points[0].get('position', [0,0,0])
            p2 = points[-1].get('position', [0,0,0])
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            print(f'{length:.2f}')
        else:
            print('0')
except:
    print('0')
" 2>/dev/null || echo "0")
        echo "  Straight length: $STRAIGHT_LENGTH mm"
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_MTIME="0"
REPORT_VALID="false"
REPORTED_PATH_LENGTH=""
REPORTED_STRAIGHT_LENGTH=""
REPORTED_TORTUOSITY=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/evar_report.json"
    "/home/ga/Documents/evar_measurements.json"
    "/home/ga/evar_measurements.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_VALID="true"
        fi
        
        echo "Found report at: $path (valid: $REPORT_VALID)"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report values
        REPORTED_PATH_LENGTH=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('path_length_mm', d.get('path_length', 0)))" 2>/dev/null || echo "")
        REPORTED_STRAIGHT_LENGTH=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('straight_length_mm', d.get('straight_length', 0)))" 2>/dev/null || echo "")
        REPORTED_TORTUOSITY=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('tortuosity_ratio', d.get('tortuosity', 0)))" 2>/dev/null || echo "")
        
        echo "  Reported: path=$REPORTED_PATH_LENGTH, straight=$REPORTED_STRAIGHT_LENGTH, tort=$REPORTED_TORTUOSITY"
        break
    fi
done

# Copy ground truth for verification
echo "Preparing ground truth for verification..."
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_centerline_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/centerline_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/centerline_ground_truth.json 2>/dev/null || true
    echo "Ground truth copied to /tmp/centerline_ground_truth.json"
fi

# Copy agent outputs to /tmp for verification
if [ -f "$OUTPUT_CURVE" ]; then
    cp "$OUTPUT_CURVE" /tmp/agent_curve.mrk.json 2>/dev/null || true
    chmod 644 /tmp/agent_curve.mrk.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_STRAIGHT" ]; then
    cp "$OUTPUT_STRAIGHT" /tmp/agent_straight.mrk.json 2>/dev/null || true
    chmod 644 /tmp/agent_straight.mrk.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_running": $SLICER_RUNNING,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "case_id": "$CASE_ID",
    "curve_exists": $CURVE_EXISTS,
    "curve_valid": $CURVE_VALID,
    "curve_path": "$CURVE_PATH",
    "curve_mtime": $CURVE_MTIME,
    "curve_length_mm": "$CURVE_LENGTH",
    "curve_points": $CURVE_POINTS,
    "straight_exists": $STRAIGHT_EXISTS,
    "straight_valid": $STRAIGHT_VALID,
    "straight_path": "$STRAIGHT_PATH",
    "straight_mtime": $STRAIGHT_MTIME,
    "straight_length_mm": "$STRAIGHT_LENGTH",
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_path": "$REPORT_PATH",
    "report_mtime": $REPORT_MTIME,
    "reported_path_length_mm": "$REPORTED_PATH_LENGTH",
    "reported_straight_length_mm": "$REPORTED_STRAIGHT_LENGTH",
    "reported_tortuosity": "$REPORTED_TORTUOSITY",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/centerline_ground_truth.json" ] && echo "true" || echo "false")
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="