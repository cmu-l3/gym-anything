#!/bin/bash
echo "=== Exporting Tumor Volume ABC/2 Estimation Result ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get sample ID
SAMPLE_ID=$(cat /tmp/task_sample_id.txt 2>/dev/null || echo "BraTS2021_00000")

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/abc2_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Initialize result variables
MEASUREMENT_A_EXISTS="false"
MEASUREMENT_B_EXISTS="false"
MEASUREMENT_C_EXISTS="false"
DIAMETER_A_MM=""
DIAMETER_B_MM=""
DIAMETER_C_MM=""
POINT_A1=""
POINT_A2=""
POINT_B1=""
POINT_B2=""
POINT_C1=""
POINT_C2=""
REPORT_EXISTS="false"
REPORTED_A=""
REPORTED_B=""
REPORTED_C=""
REPORTED_VOLUME=""

# Export measurements from Slicer if running
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Exporting measurements from Slicer..."
    
    cat > /tmp/export_abc2_measurements.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Find all line markup nodes
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

measurements = []
for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        
        # Calculate length
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        # Calculate direction vector
        direction = [(p2[i] - p1[i]) / length if length > 0 else 0 for i in range(3)]
        
        measurement = {
            "name": node.GetName(),
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2],
            "direction": [round(d, 4) for d in direction],
            "z_position": round((p1[2] + p2[2]) / 2, 2)
        }
        measurements.append(measurement)
        print(f"  Measurement '{node.GetName()}': {length:.2f} mm")
        
        # Save individual markup files based on name
        name_lower = node.GetName().lower()
        if 'a' in name_lower or 'long' in name_lower or '1' in name_lower:
            mrk_path = os.path.join(output_dir, "measurement_A.mrk.json")
            slicer.util.saveNode(node, mrk_path)
            print(f"  Saved as measurement_A")
        elif 'b' in name_lower or 'perp' in name_lower or '2' in name_lower:
            mrk_path = os.path.join(output_dir, "measurement_B.mrk.json")
            slicer.util.saveNode(node, mrk_path)
            print(f"  Saved as measurement_B")
        elif 'c' in name_lower or 'cranio' in name_lower or '3' in name_lower:
            mrk_path = os.path.join(output_dir, "measurement_C.mrk.json")
            slicer.util.saveNode(node, mrk_path)
            print(f"  Saved as measurement_C")

# If we have exactly 3 measurements, assign by size (A=largest, B=medium, C=smallest in z-diff)
if len(measurements) >= 3 and not os.path.exists(os.path.join(output_dir, "measurement_A.mrk.json")):
    # Sort by length for A, B assignment
    sorted_by_length = sorted(measurements, key=lambda x: x['length_mm'], reverse=True)
    
    # Try to identify which is axial (small z variation) vs craniocaudal (large z variation)
    for i, node in enumerate(line_nodes):
        if i >= 3:
            break
        if i == 0:
            mrk_path = os.path.join(output_dir, "measurement_A.mrk.json")
        elif i == 1:
            mrk_path = os.path.join(output_dir, "measurement_B.mrk.json")
        else:
            mrk_path = os.path.join(output_dir, "measurement_C.mrk.json")
        slicer.util.saveNode(node, mrk_path)

# Save all measurements summary
if measurements:
    summary_path = os.path.join(output_dir, "all_measurements.json")
    with open(summary_path, 'w') as f:
        json.dump({"measurements": measurements, "count": len(measurements)}, f, indent=2)
    print(f"Saved measurement summary to {summary_path}")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_abc2_measurements.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 15
    pkill -f "export_abc2_measurements" 2>/dev/null || true
fi

# Parse measurement files
parse_markup_file() {
    local file=$1
    if [ -f "$file" ]; then
        python3 << PYEOF
import json
import math

try:
    with open("$file") as f:
        data = json.load(f)
    
    # Handle Slicer markup format
    if 'markups' in data:
        for m in data.get('markups', []):
            cps = m.get('controlPoints', [])
            if len(cps) >= 2:
                p1 = cps[0].get('position', [0,0,0])
                p2 = cps[1].get('position', [0,0,0])
                length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                print(f"LENGTH:{length:.2f}")
                print(f"P1:{p1[0]:.2f},{p1[1]:.2f},{p1[2]:.2f}")
                print(f"P2:{p2[0]:.2f},{p2[1]:.2f},{p2[2]:.2f}")
                break
except Exception as e:
    print(f"ERROR:{e}")
PYEOF
    fi
}

# Check measurement A
MEAS_A_FILE="$BRATS_DIR/measurement_A.mrk.json"
if [ -f "$MEAS_A_FILE" ]; then
    MEASUREMENT_A_EXISTS="true"
    MEAS_A_OUTPUT=$(parse_markup_file "$MEAS_A_FILE")
    DIAMETER_A_MM=$(echo "$MEAS_A_OUTPUT" | grep "^LENGTH:" | cut -d: -f2)
    POINT_A1=$(echo "$MEAS_A_OUTPUT" | grep "^P1:" | cut -d: -f2)
    POINT_A2=$(echo "$MEAS_A_OUTPUT" | grep "^P2:" | cut -d: -f2)
fi

# Check measurement B
MEAS_B_FILE="$BRATS_DIR/measurement_B.mrk.json"
if [ -f "$MEAS_B_FILE" ]; then
    MEASUREMENT_B_EXISTS="true"
    MEAS_B_OUTPUT=$(parse_markup_file "$MEAS_B_FILE")
    DIAMETER_B_MM=$(echo "$MEAS_B_OUTPUT" | grep "^LENGTH:" | cut -d: -f2)
    POINT_B1=$(echo "$MEAS_B_OUTPUT" | grep "^P1:" | cut -d: -f2)
    POINT_B2=$(echo "$MEAS_B_OUTPUT" | grep "^P2:" | cut -d: -f2)
fi

# Check measurement C
MEAS_C_FILE="$BRATS_DIR/measurement_C.mrk.json"
if [ -f "$MEAS_C_FILE" ]; then
    MEASUREMENT_C_EXISTS="true"
    MEAS_C_OUTPUT=$(parse_markup_file "$MEAS_C_FILE")
    DIAMETER_C_MM=$(echo "$MEAS_C_OUTPUT" | grep "^LENGTH:" | cut -d: -f2)
    POINT_C1=$(echo "$MEAS_C_OUTPUT" | grep "^P1:" | cut -d: -f2)
    POINT_C2=$(echo "$MEAS_C_OUTPUT" | grep "^P2:" | cut -d: -f2)
fi

# Parse report file
REPORT_FILE="$BRATS_DIR/volume_estimate.txt"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORTED_A=$(grep -i "A_diameter_mm" "$REPORT_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "")
    REPORTED_B=$(grep -i "B_diameter_mm" "$REPORT_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "")
    REPORTED_C=$(grep -i "C_diameter_mm" "$REPORT_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "")
    REPORTED_VOLUME=$(grep -i "estimated_volume_ml" "$REPORT_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "")
fi

# Count total line measurements (from summary if exists)
TOTAL_MEASUREMENTS=0
if [ -f "$BRATS_DIR/all_measurements.json" ]; then
    TOTAL_MEASUREMENTS=$(python3 -c "import json; print(json.load(open('$BRATS_DIR/all_measurements.json')).get('count', 0))" 2>/dev/null || echo "0")
fi

# Check for any new markup files created during task
NEW_MARKUPS=$(find "$BRATS_DIR" -name "*.mrk.json" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# Check screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
if [ -f "/tmp/abc2_final.png" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "/tmp/abc2_final.png" 2>/dev/null | cut -f1 || echo "0")
fi

# Load ground truth for comparison
GT_VOLUME=""
GT_REF_A=""
GT_REF_B=""
GT_REF_C=""
if [ -f "/tmp/abc2_ground_truth.json" ]; then
    GT_VOLUME=$(python3 -c "import json; print(json.load(open('/tmp/abc2_ground_truth.json')).get('gt_volume_ml', ''))" 2>/dev/null || echo "")
    GT_REF_A=$(python3 -c "import json; print(json.load(open('/tmp/abc2_ground_truth.json')).get('ref_diameter_A_mm', ''))" 2>/dev/null || echo "")
    GT_REF_B=$(python3 -c "import json; print(json.load(open('/tmp/abc2_ground_truth.json')).get('ref_diameter_B_mm', ''))" 2>/dev/null || echo "")
    GT_REF_C=$(python3 -c "import json; print(json.load(open('/tmp/abc2_ground_truth.json')).get('ref_diameter_C_mm', ''))" 2>/dev/null || echo "")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sample_id": "$SAMPLE_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_A_exists": $MEASUREMENT_A_EXISTS,
    "measurement_B_exists": $MEASUREMENT_B_EXISTS,
    "measurement_C_exists": $MEASUREMENT_C_EXISTS,
    "diameter_A_mm": "$DIAMETER_A_MM",
    "diameter_B_mm": "$DIAMETER_B_MM",
    "diameter_C_mm": "$DIAMETER_C_MM",
    "point_A1": "$POINT_A1",
    "point_A2": "$POINT_A2",
    "point_B1": "$POINT_B1",
    "point_B2": "$POINT_B2",
    "point_C1": "$POINT_C1",
    "point_C2": "$POINT_C2",
    "report_exists": $REPORT_EXISTS,
    "reported_A_mm": "$REPORTED_A",
    "reported_B_mm": "$REPORTED_B",
    "reported_C_mm": "$REPORTED_C",
    "reported_volume_ml": "$REPORTED_VOLUME",
    "total_measurements": $TOTAL_MEASUREMENTS,
    "new_markups_created": $NEW_MARKUPS,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "gt_volume_ml": "$GT_VOLUME",
    "gt_ref_A_mm": "$GT_REF_A",
    "gt_ref_B_mm": "$GT_REF_B",
    "gt_ref_C_mm": "$GT_REF_C",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/abc2_task_result.json 2>/dev/null || sudo rm -f /tmp/abc2_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/abc2_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/abc2_task_result.json
chmod 666 /tmp/abc2_task_result.json 2>/dev/null || sudo chmod 666 /tmp/abc2_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/abc2_task_result.json"
cat /tmp/abc2_task_result.json
echo ""
echo "=== Export Complete ==="