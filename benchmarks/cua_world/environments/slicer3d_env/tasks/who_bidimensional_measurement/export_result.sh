#!/bin/bash
echo "=== Exporting WHO Bidimensional Measurement Results ==="

source /workspace/scripts/task_utils.sh

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENTS="$BRATS_DIR/who_measurements.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/who_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/who_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any markups from Slicer before checking files
    cat > /tmp/export_who_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Find all line markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup node(s)")

all_lines = []
for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        
        # Calculate length
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        line_data = {
            "name": node.GetName(),
            "type": "Line",
            "length_mm": round(length, 2),
            "controlPoints": [
                {"position": p1},
                {"position": p2}
            ]
        }
        all_lines.append(line_data)
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        print(f"    P1: {p1}")
        print(f"    P2: {p2}")

# Save markups
if all_lines:
    output_path = os.path.join(output_dir, "who_measurements.mrk.json")
    with open(output_path, "w") as f:
        json.dump({"markups": all_lines}, f, indent=2)
    print(f"Saved {len(all_lines)} line(s) to {output_path}")
    
    # Also save individual nodes using Slicer's native format
    for i, node in enumerate(line_nodes):
        node_path = os.path.join(output_dir, f"line_{i}.mrk.json")
        slicer.util.saveNode(node, node_path)
else:
    print("No line markups found")
PYEOF

    # Run export in Slicer (briefly)
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_who_markups.py --no-main-window > /tmp/slicer_export_who.log 2>&1 &
    sleep 8
    pkill -f "export_who_markups" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENTS_EXISTS="false"
MEASUREMENTS_PATH=""
RULER_COUNT=0
LINE_DATA="[]"

# Search for measurement files
POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENTS"
    "$BRATS_DIR/who_measurements.mrk.json"
    "$BRATS_DIR/measurements.mrk.json"
    "$BRATS_DIR/line_0.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENTS_EXISTS="true"
        MEASUREMENTS_PATH="$path"
        echo "Found measurements at: $path"
        
        # Copy to expected location if needed
        if [ "$path" != "$OUTPUT_MEASUREMENTS" ]; then
            cp "$path" "$OUTPUT_MEASUREMENTS" 2>/dev/null || true
        fi
        break
    fi
done

# Extract line data and count from measurement file
if [ "$MEASUREMENTS_EXISTS" = "true" ]; then
    LINE_DATA=$(python3 << PYEOF
import json
import sys

try:
    with open("$MEASUREMENTS_PATH") as f:
        data = json.load(f)
    
    markups = data.get('markups', [])
    
    # Filter for line-type markups
    lines = []
    for m in markups:
        if m.get('type') == 'Line' or 'controlPoints' in m:
            lines.append(m)
    
    print(json.dumps(lines))
except Exception as e:
    print("[]")
PYEOF
)
    
    RULER_COUNT=$(echo "$LINE_DATA" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    echo "Found $RULER_COUNT ruler/line measurement(s)"
fi

# Check for report file
REPORT_EXISTS="false"
AGENT_D1=""
AGENT_D2=""
AGENT_PRODUCT=""
AGENT_SLICE=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/who_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/who_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract values from report
        AGENT_D1=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('longest_diameter_mm', d.get('d1_mm', d.get('d1', 0))))" 2>/dev/null || echo "0")
        AGENT_D2=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('perpendicular_diameter_mm', d.get('d2_mm', d.get('d2', 0))))" 2>/dev/null || echo "0")
        AGENT_PRODUCT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('bidimensional_product_mm2', d.get('product', d.get('area', 0))))" 2>/dev/null || echo "0")
        AGENT_SLICE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('measurement_slice', d.get('slice', 0)))" 2>/dev/null || echo "0")
        
        echo "  D1: $AGENT_D1 mm"
        echo "  D2: $AGENT_D2 mm"
        echo "  Product: $AGENT_PRODUCT mm²"
        echo "  Slice: $AGENT_SLICE"
        break
    fi
done

# If no report but we have measurements, try to extract D1 and D2 from the lines
if [ "$REPORT_EXISTS" = "false" ] && [ "$MEASUREMENTS_EXISTS" = "true" ] && [ "$RULER_COUNT" -ge 1 ]; then
    echo "No report found, extracting values from measurements..."
    
    EXTRACTED=$(python3 << PYEOF
import json
import sys

try:
    lines = $LINE_DATA
    
    if len(lines) >= 1:
        d1 = lines[0].get('length_mm', 0)
        d2 = lines[1].get('length_mm', 0) if len(lines) >= 2 else 0
        product = d1 * d2
        print(json.dumps({"d1": d1, "d2": d2, "product": product}))
    else:
        print(json.dumps({"d1": 0, "d2": 0, "product": 0}))
except:
    print(json.dumps({"d1": 0, "d2": 0, "product": 0}))
PYEOF
)
    
    AGENT_D1=$(echo "$EXTRACTED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('d1', 0))" 2>/dev/null || echo "0")
    AGENT_D2=$(echo "$EXTRACTED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('d2', 0))" 2>/dev/null || echo "0")
    AGENT_PRODUCT=$(echo "$EXTRACTED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('product', 0))" 2>/dev/null || echo "0")
fi

# Calculate angle between measurements if we have 2 lines
ANGLE_DEVIATION="90"
if [ "$RULER_COUNT" -ge 2 ]; then
    ANGLE_DEVIATION=$(python3 << PYEOF
import json
import numpy as np
import sys

try:
    lines = $LINE_DATA
    
    if len(lines) >= 2:
        # Get control points for both lines
        line1_pts = lines[0].get('controlPoints', [])
        line2_pts = lines[1].get('controlPoints', [])
        
        if len(line1_pts) >= 2 and len(line2_pts) >= 2:
            p1_1 = np.array(line1_pts[0].get('position', [0,0,0]))
            p1_2 = np.array(line1_pts[1].get('position', [0,0,0]))
            p2_1 = np.array(line2_pts[0].get('position', [0,0,0]))
            p2_2 = np.array(line2_pts[1].get('position', [0,0,0]))
            
            # Direction vectors
            v1 = p1_2 - p1_1
            v2 = p2_2 - p2_1
            
            # Use 2D (axial plane) for angle calculation
            v1_2d = v1[:2]
            v2_2d = v2[:2]
            
            norm1 = np.linalg.norm(v1_2d)
            norm2 = np.linalg.norm(v2_2d)
            
            if norm1 > 0 and norm2 > 0:
                cos_angle = np.dot(v1_2d, v2_2d) / (norm1 * norm2)
                cos_angle = np.clip(cos_angle, -1, 1)
                angle_rad = np.arccos(cos_angle)
                angle_deg = np.degrees(angle_rad)
                
                # Deviation from 90 degrees
                deviation = abs(90 - angle_deg)
                print(f"{deviation:.2f}")
            else:
                print("90")
        else:
            print("90")
    else:
        print("90")
except Exception as e:
    print("90")
PYEOF
)
    echo "Angle deviation from perpendicular: $ANGLE_DEVIATION degrees"
fi

# Check file timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ "$MEASUREMENTS_EXISTS" = "true" ] && [ -f "$OUTPUT_MEASUREMENTS" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENTS" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_who_gt.json" /tmp/who_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/who_ground_truth.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/who_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurements_file_exists": $MEASUREMENTS_EXISTS,
    "report_file_exists": $REPORT_EXISTS,
    "ruler_count": $RULER_COUNT,
    "agent_d1_mm": "$AGENT_D1",
    "agent_d2_mm": "$AGENT_D2",
    "agent_product_mm2": "$AGENT_PRODUCT",
    "agent_slice": "$AGENT_SLICE",
    "angle_deviation_degrees": "$ANGLE_DEVIATION",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "sample_id": "$SAMPLE_ID",
    "line_data": $LINE_DATA,
    "screenshot_exists": $([ -f "/tmp/who_final.png" ] && echo "true" || echo "false")
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