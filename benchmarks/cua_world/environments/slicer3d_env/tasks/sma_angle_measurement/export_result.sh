#!/bin/bash
echo "=== Exporting SMA Angle Measurement Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Get timing information
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ELAPSED=$((TASK_END - TASK_START))

# Get the case ID used
CASE_ID="amos_0001"
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MARKUP="$AMOS_DIR/sma_angle.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/sma_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/sma_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any angle measurements from Slicer
    cat > /tmp/export_sma_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

measurements = []

# Check for angle markups
angle_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsAngleNode")
print(f"Found {len(angle_nodes)} angle markup(s)")

for node in angle_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 3:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]  # vertex
        p3 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        node.GetNthControlPointPosition(2, p3)
        
        # Calculate angle
        import numpy as np
        v1 = np.array(p1) - np.array(p2)
        v2 = np.array(p3) - np.array(p2)
        dot = np.dot(v1, v2)
        norms = np.linalg.norm(v1) * np.linalg.norm(v2)
        if norms > 0:
            cos_angle = np.clip(dot / norms, -1, 1)
            angle_deg = np.degrees(np.arccos(cos_angle))
        else:
            angle_deg = 0
        
        measurement = {
            "name": node.GetName(),
            "type": "angle",
            "angle_degrees": float(angle_deg),
            "p1": list(p1),
            "p2_vertex": list(p2),
            "p3": list(p3),
        }
        measurements.append(measurement)
        print(f"  Angle '{node.GetName()}': {angle_deg:.1f}°")
        
        # Save the markup node
        mrk_path = os.path.join(output_dir, "sma_angle.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved to: {mrk_path}")

# Also check for line markups (for distance measurement)
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
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": float(length),
            "p1": list(p1),
            "p2": list(p2),
        }
        measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm")

# Save all measurements
if measurements:
    all_meas_path = os.path.join(output_dir, "all_measurements.json")
    with open(all_meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Exported {len(measurements)} measurements to {all_meas_path}")

print("Export complete")
PYEOF
    
    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_sma_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_sma_meas" 2>/dev/null || true
fi

# Check for markup file
MARKUP_EXISTS="false"
MARKUP_PATH=""
MARKUP_SIZE=0
MARKUP_MTIME=0
MEASURED_ANGLE=""
ANGLE_VERTEX=""

POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MARKUP"
    "$AMOS_DIR/sma_angle.mrk.json"
    "$AMOS_DIR/angle.mrk.json"
    "$AMOS_DIR/A.mrk.json"
    "/home/ga/Documents/sma_angle.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUP_EXISTS="true"
        MARKUP_PATH="$path"
        MARKUP_SIZE=$(stat -c%s "$path" 2>/dev/null || echo "0")
        MARKUP_MTIME=$(stat -c%Y "$path" 2>/dev/null || echo "0")
        echo "Found markup at: $path"
        
        # Copy to expected location if needed
        if [ "$path" != "$OUTPUT_MARKUP" ]; then
            cp "$path" "$OUTPUT_MARKUP" 2>/dev/null || true
        fi
        
        # Extract angle from markup
        MEASURED_ANGLE=$(python3 << PYEOF
import json
import numpy as np
try:
    with open("$path", 'r') as f:
        data = json.load(f)
    
    # Slicer markup format
    if 'markups' in data:
        for markup in data['markups']:
            if markup.get('type') == 'Angle':
                # Try measurements first
                for m in markup.get('measurements', []):
                    if 'angle' in m.get('name', '').lower():
                        print(f"{m.get('value', 0):.2f}")
                        break
                else:
                    # Calculate from control points
                    cps = markup.get('controlPoints', [])
                    if len(cps) >= 3:
                        p1 = np.array(cps[0].get('position', [0,0,0]))
                        p2 = np.array(cps[1].get('position', [0,0,0]))
                        p3 = np.array(cps[2].get('position', [0,0,0]))
                        v1 = p1 - p2
                        v2 = p3 - p2
                        dot = np.dot(v1, v2)
                        norms = np.linalg.norm(v1) * np.linalg.norm(v2)
                        if norms > 0:
                            cos_a = np.clip(dot / norms, -1, 1)
                            angle = np.degrees(np.arccos(cos_a))
                            print(f"{angle:.2f}")
except Exception as e:
    print("")
PYEOF
)
        
        # Extract vertex position
        ANGLE_VERTEX=$(python3 << PYEOF
import json
try:
    with open("$path", 'r') as f:
        data = json.load(f)
    if 'markups' in data:
        for markup in data['markups']:
            if markup.get('type') == 'Angle':
                cps = markup.get('controlPoints', [])
                if len(cps) >= 2:
                    pos = cps[1].get('position', [0,0,0])
                    print(f"{pos[0]:.1f},{pos[1]:.1f},{pos[2]:.1f}")
except:
    print("")
PYEOF
)
        break
    fi
done

# Check if markup was created/modified during task
MARKUP_CREATED_DURING_TASK="false"
if [ "$MARKUP_EXISTS" = "true" ] && [ "$MARKUP_MTIME" -gt "$TASK_START" ]; then
    MARKUP_CREATED_DURING_TASK="true"
fi

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_SIZE=0
REPORTED_ANGLE=""
REPORTED_DISTANCE=""
REPORTED_CLASSIFICATION=""
REPORT_VALID="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/sma_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/sma_report.json"
    "/home/ga/sma_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_SIZE=$(stat -c%s "$path" 2>/dev/null || echo "0")
        echo "Found report at: $path"
        
        # Copy to expected location if needed
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        eval $(python3 << PYEOF
import json
try:
    with open("$path", 'r') as f:
        data = json.load(f)
    
    angle = data.get('sma_angle_degrees', data.get('angle_degrees', data.get('angle', '')))
    distance = data.get('aortomesenteric_distance_mm', data.get('distance_mm', data.get('distance', '')))
    classification = data.get('classification', '')
    
    valid = "true" if (angle != '' and classification != '') else "false"
    
    print(f"REPORTED_ANGLE='{angle}'")
    print(f"REPORTED_DISTANCE='{distance}'")
    print(f"REPORTED_CLASSIFICATION='{classification}'")
    print(f"REPORT_VALID='{valid}'")
except Exception as e:
    print("REPORT_VALID='false'")
PYEOF
)
        break
    fi
done

# Check for screenshot evidence
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/sma_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Check if task was actually attempted
TASK_ATTEMPTED="false"
if [ "$MARKUP_EXISTS" = "true" ] || [ "$REPORT_EXISTS" = "true" ]; then
    TASK_ATTEMPTED="true"
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${CASE_ID}_sma_gt.json" /tmp/sma_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/sma_ground_truth.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/sma_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "sma_angle_measurement@1",
    "case_id": "$CASE_ID",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "elapsed_seconds": $ELAPSED,
    "slicer_was_running": $SLICER_RUNNING,
    "task_attempted": $TASK_ATTEMPTED,
    "markup_file": {
        "exists": $MARKUP_EXISTS,
        "path": "$MARKUP_PATH",
        "size_bytes": $MARKUP_SIZE,
        "mtime": $MARKUP_MTIME,
        "created_during_task": $MARKUP_CREATED_DURING_TASK,
        "measured_angle_degrees": "$MEASURED_ANGLE",
        "vertex_position": "$ANGLE_VERTEX"
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "path": "$REPORT_PATH",
        "size_bytes": $REPORT_SIZE,
        "valid_format": $REPORT_VALID,
        "reported_angle_degrees": "$REPORTED_ANGLE",
        "reported_distance_mm": "$REPORTED_DISTANCE",
        "classification": "$REPORTED_CLASSIFICATION"
    },
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "output_paths": {
        "markup": "$OUTPUT_MARKUP",
        "report": "$OUTPUT_REPORT",
        "screenshot": "/tmp/sma_final.png"
    }
}
EOF

# Save result
rm -f /tmp/sma_angle_result.json 2>/dev/null || sudo rm -f /tmp/sma_angle_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/sma_angle_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/sma_angle_result.json
chmod 666 /tmp/sma_angle_result.json 2>/dev/null || sudo chmod 666 /tmp/sma_angle_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result exported to: /tmp/sma_angle_result.json"
cat /tmp/sma_angle_result.json

# Prepare files for verification
mkdir -p /tmp/verification_files
cp "$OUTPUT_MARKUP" /tmp/verification_files/ 2>/dev/null || true
cp "$OUTPUT_REPORT" /tmp/verification_files/ 2>/dev/null || true
cp /tmp/sma_final.png /tmp/verification_files/ 2>/dev/null || true

echo ""
echo "=== Export Complete ==="