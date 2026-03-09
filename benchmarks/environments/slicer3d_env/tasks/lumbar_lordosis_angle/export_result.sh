#!/bin/bash
echo "=== Exporting Lumbar Lordosis Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MARKUPS="$AMOS_DIR/lumbar_lordosis_markups.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/lumbar_lordosis_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/lordosis_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"

    # Try to export measurements from Slicer
    cat > /tmp/export_lordosis_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []
line_data = []

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
        
        # Calculate line direction vector
        direction = [p2[i] - p1[i] for i in range(3)]
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "direction": direction,
            "midpoint_z": (p1[2] + p2[2]) / 2
        }
        all_measurements.append(measurement)
        line_data.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm at z={measurement['midpoint_z']:.1f}")

# Check for angle markups
angle_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsAngleNode")
print(f"Found {len(angle_nodes)} angle markup(s)")

for node in angle_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 3:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        p3 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        node.GetNthControlPointPosition(2, p3)
        
        # Get the angle value
        angle = node.GetAngleDegrees()
        
        measurement = {
            "name": node.GetName(),
            "type": "angle",
            "angle_degrees": angle,
            "points": [p1, p2, p3]
        }
        all_measurements.append(measurement)
        print(f"  Angle '{node.GetName()}': {angle:.1f}°")

# Calculate angle between two lines if we have exactly 2 lines
calculated_angle = None
if len(line_data) >= 2:
    # Sort lines by z position (L1 should be higher z than S1)
    line_data.sort(key=lambda x: x['midpoint_z'], reverse=True)
    
    # Get direction vectors
    dir1 = line_data[0]['direction']  # Upper line (L1)
    dir2 = line_data[1]['direction']  # Lower line (S1)
    
    # Calculate angle between lines
    dot = sum(a*b for a,b in zip(dir1, dir2))
    mag1 = math.sqrt(sum(a**2 for a in dir1))
    mag2 = math.sqrt(sum(a**2 for a in dir2))
    
    if mag1 > 0 and mag2 > 0:
        cos_angle = dot / (mag1 * mag2)
        cos_angle = max(-1, min(1, cos_angle))  # Clamp to valid range
        angle_rad = math.acos(abs(cos_angle))
        calculated_angle = math.degrees(angle_rad)
        print(f"  Calculated angle between lines: {calculated_angle:.1f}°")

# Save all measurements
if all_measurements:
    meas_data = {
        "measurements": all_measurements,
        "calculated_lordosis_angle": calculated_angle,
        "num_lines": len(line_data),
        "line_positions": [{"name": l["name"], "z_mm": l["midpoint_z"]} for l in line_data]
    }
    meas_path = os.path.join(output_dir, "lumbar_lordosis_markups.mrk.json")
    with open(meas_path, "w") as f:
        json.dump(meas_data, f, indent=2)
    print(f"Exported measurements to {meas_path}")

    # Also save individual markup nodes
    for node in line_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, mrk_path)
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_lordosis_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_lordosis_meas" 2>/dev/null || true
fi

# Check for markup files created by agent
MARKUP_EXISTS="false"
MARKUP_PATH=""
MEASURED_ANGLE=""
NUM_LINES="0"
L1_Z=""
S1_Z=""

POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MARKUPS"
    "$AMOS_DIR/lumbar_lordosis_markups.mrk.json"
    "$AMOS_DIR/markups.mrk.json"
    "$AMOS_DIR/lordosis.mrk.json"
    "/home/ga/Documents/lumbar_lordosis_markups.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUP_EXISTS="true"
        MARKUP_PATH="$path"
        echo "Found markups at: $path"
        if [ "$path" != "$OUTPUT_MARKUPS" ]; then
            cp "$path" "$OUTPUT_MARKUPS" 2>/dev/null || true
        fi
        
        # Extract calculated angle and line info
        MEASURED_ANGLE=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
angle = data.get('calculated_lordosis_angle')
if angle:
    print(f'{angle:.2f}')
" 2>/dev/null || echo "")
        
        NUM_LINES=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('num_lines', 0))
" 2>/dev/null || echo "0")

        # Get line Z positions
        LINE_POSITIONS=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
positions = data.get('line_positions', [])
for p in positions:
    print(f\"{p.get('name', 'unknown')}:{p.get('z_mm', 0):.1f}\")
" 2>/dev/null || echo "")
        echo "Line positions: $LINE_POSITIONS"
        
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_ANGLE=""
REPORTED_CLASSIFICATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/lumbar_lordosis_report.json"
    "$AMOS_DIR/lordosis_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/lumbar_lordosis_report.json"
    "/home/ga/lumbar_lordosis_report.json"
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
        REPORTED_ANGLE=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
angle = d.get('angle_degrees', d.get('lordosis_angle', d.get('angle', '')))
if angle:
    print(f'{float(angle):.2f}')
" 2>/dev/null || echo "")

        REPORTED_CLASSIFICATION=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
print(d.get('classification', ''))
" 2>/dev/null || echo "")

        REPORTED_L1=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
print(str(d.get('l1_identified', '')).lower())
" 2>/dev/null || echo "")

        REPORTED_S1=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
print(str(d.get('s1_identified', '')).lower())
" 2>/dev/null || echo "")
        
        echo "Reported angle: $REPORTED_ANGLE°"
        echo "Reported classification: $REPORTED_CLASSIFICATION"
        break
    fi
done

# Check file timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_MARKUPS" ]; then
    MARKUP_MTIME=$(stat -c %Y "$OUTPUT_MARKUPS" 2>/dev/null || echo "0")
    if [ "$MARKUP_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${CASE_ID}_lordosis_gt.json" /tmp/lordosis_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/lordosis_ground_truth.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "markup_exists": $MARKUP_EXISTS,
    "markup_path": "$MARKUP_PATH",
    "num_lines": $NUM_LINES,
    "measured_angle_degrees": "$MEASURED_ANGLE",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_angle_degrees": "$REPORTED_ANGLE",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_l1_identified": "$REPORTED_L1",
    "reported_s1_identified": "$REPORTED_S1",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_exists": $([ -f "/tmp/lordosis_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/lordosis_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/lordosis_task_result.json 2>/dev/null || sudo rm -f /tmp/lordosis_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/lordosis_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/lordosis_task_result.json
chmod 666 /tmp/lordosis_task_result.json 2>/dev/null || sudo chmod 666 /tmp/lordosis_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/lordosis_task_result.json
echo ""
echo "=== Export Complete ==="