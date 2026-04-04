#!/bin/bash
echo "=== Exporting Carinal Angle Measurement Result ==="

source /workspace/scripts/task_utils.sh

AIRWAY_DIR="/home/ga/Documents/SlicerData/Airway"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENT="$AIRWAY_DIR/carinal_angle.mrk.json"
OUTPUT_REPORT="$AIRWAY_DIR/carinal_report.json"

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/carinal_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export angle measurements from Slicer
    cat > /tmp/export_angle_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Airway"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Check for angle markups
angle_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsAngleNode")
print(f"Found {len(angle_nodes)} angle markup(s)")

for node in angle_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 3:
        # Get the three points of the angle
        p1 = [0.0, 0.0, 0.0]  # First arm endpoint
        p2 = [0.0, 0.0, 0.0]  # Vertex
        p3 = [0.0, 0.0, 0.0]  # Second arm endpoint
        
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)  # Vertex is middle point
        node.GetNthControlPointPosition(2, p3)
        
        # Calculate angle
        v1 = [p1[i] - p2[i] for i in range(3)]
        v2 = [p3[i] - p2[i] for i in range(3)]
        
        dot = sum(a*b for a, b in zip(v1, v2))
        mag1 = math.sqrt(sum(a*a for a in v1))
        mag2 = math.sqrt(sum(a*a for a in v2))
        
        if mag1 > 0 and mag2 > 0:
            cos_angle = dot / (mag1 * mag2)
            cos_angle = max(-1, min(1, cos_angle))  # Clamp to valid range
            angle_rad = math.acos(cos_angle)
            angle_deg = math.degrees(angle_rad)
        else:
            angle_deg = 0.0
        
        measurement = {
            "name": node.GetName(),
            "type": "angle",
            "angle_degrees": angle_deg,
            "vertex": p2,
            "arm1_endpoint": p1,
            "arm2_endpoint": p3,
            "vertex_z_mm": p2[2]
        }
        all_measurements.append(measurement)
        print(f"  Angle '{node.GetName()}': {angle_deg:.1f}°")
        print(f"    Vertex at z={p2[2]:.1f}mm")
        
        # Save the markup node
        mrk_path = os.path.join(output_dir, "carinal_angle.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved markup to {mrk_path}")

# Also check for line markups (in case agent used rulers)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
        all_measurements.append({
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2
        })

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "all_measurements.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No angle measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_angle_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_angle_meas" 2>/dev/null || true
fi

# ============================================================
# Check for measurement file
# ============================================================
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_ANGLE=""
MEASUREMENT_Z_MM=""
FILE_CREATED_DURING_TASK="false"

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AIRWAY_DIR/carinal_angle.mrk.json"
    "$AIRWAY_DIR/angle.mrk.json"
    "$AIRWAY_DIR/all_measurements.json"
    "/home/ga/Documents/carinal_angle.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        
        # Check if created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
        
        echo "Found measurement at: $path"
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Try to extract angle from measurement
        MEASURED_ANGLE=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)

# Handle Slicer markup format
if 'markups' in data:
    for markup in data.get('markups', []):
        if markup.get('type') == 'Angle':
            measurements = markup.get('measurements', [])
            for m in measurements:
                if 'angle' in m.get('name', '').lower():
                    print(f\"{m.get('value', 0):.2f}\")
                    break
            else:
                # Try controlPoints
                points = markup.get('controlPoints', [])
                if len(points) >= 3:
                    import math
                    p1 = points[0].get('position', [0,0,0])
                    p2 = points[1].get('position', [0,0,0])  # vertex
                    p3 = points[2].get('position', [0,0,0])
                    v1 = [p1[i] - p2[i] for i in range(3)]
                    v2 = [p3[i] - p2[i] for i in range(3)]
                    dot = sum(a*b for a, b in zip(v1, v2))
                    mag1 = math.sqrt(sum(a*a for a in v1))
                    mag2 = math.sqrt(sum(a*a for a in v2))
                    if mag1 > 0 and mag2 > 0:
                        cos_angle = max(-1, min(1, dot / (mag1 * mag2)))
                        angle = math.degrees(math.acos(cos_angle))
                        print(f\"{angle:.2f}\")
                        break
            break
# Handle custom format
elif 'measurements' in data:
    for m in data.get('measurements', []):
        if m.get('type') == 'angle':
            print(f\"{m.get('angle_degrees', 0):.2f}\")
            break
" 2>/dev/null || echo "")

        # Extract vertex z position
        MEASUREMENT_Z_MM=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)

if 'markups' in data:
    for markup in data.get('markups', []):
        points = markup.get('controlPoints', [])
        if len(points) >= 3:
            # Vertex is middle point (index 1)
            pos = points[1].get('position', [0,0,0])
            print(f\"{pos[2]:.2f}\")
            break
elif 'measurements' in data:
    for m in data.get('measurements', []):
        if m.get('type') == 'angle':
            vertex = m.get('vertex', [0,0,0])
            print(f\"{vertex[2]:.2f}\")
            break
" 2>/dev/null || echo "")
        
        break
    fi
done

echo "Measured angle: $MEASURED_ANGLE degrees"
echo "Measurement Z position: $MEASUREMENT_Z_MM mm"

# ============================================================
# Check for report file
# ============================================================
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_ANGLE=""
REPORTED_CLASSIFICATION=""
REPORTED_LEVEL=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AIRWAY_DIR/carinal_report.json"
    "$AIRWAY_DIR/report.json"
    "/home/ga/Documents/carinal_report.json"
    "/home/ga/carinal_report.json"
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
keys = ['measured_angle_degrees', 'angle_degrees', 'angle', 'carinal_angle']
for k in keys:
    if k in d:
        print(d[k])
        break
" 2>/dev/null || echo "")
        
        REPORTED_CLASSIFICATION=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
print(d.get('classification', d.get('assessment', '')))
" 2>/dev/null || echo "")
        
        REPORTED_LEVEL=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
print(d.get('vertebral_level', d.get('level', '')))
" 2>/dev/null || echo "")
        
        break
    fi
done

# Use reported angle if measurement extraction failed
if [ -z "$MEASURED_ANGLE" ] && [ -n "$REPORTED_ANGLE" ]; then
    MEASURED_ANGLE="$REPORTED_ANGLE"
fi

# ============================================================
# Copy ground truth for verification
# ============================================================
if [ -f "$GROUND_TRUTH_DIR/carinal_ground_truth.json" ]; then
    cp "$GROUND_TRUTH_DIR/carinal_ground_truth.json" /tmp/carinal_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/carinal_ground_truth.json 2>/dev/null || true
fi

# ============================================================
# Close Slicer
# ============================================================
echo "Closing 3D Slicer..."
close_slicer

# ============================================================
# Create result JSON
# ============================================================
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/carinal_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "measured_angle_degrees": "$MEASURED_ANGLE",
    "measurement_z_mm": "$MEASUREMENT_Z_MM",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_angle_degrees": "$REPORTED_ANGLE",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_vertebral_level": "$REPORTED_LEVEL",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/carinal_task_result.json 2>/dev/null || sudo rm -f /tmp/carinal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/carinal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/carinal_task_result.json
chmod 666 /tmp/carinal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/carinal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/carinal_task_result.json
echo ""
echo "=== Export Complete ==="