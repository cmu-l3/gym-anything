#!/bin/bash
echo "=== Exporting Lung Nodule Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get patient ID
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_MEASUREMENT="$LIDC_DIR/nodule_measurement.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/lungrads_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/lung_nodule_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_nodule_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

measurements = []

# Get line/ruler markups
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
            "length_mm": length,
            "p1_ras": p1,
            "p2_ras": p2,
            "midpoint_ras": [(a+b)/2 for a,b in zip(p1, p2)]
        })
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        
        # Save individual markup
        mrk_path = os.path.join(output_dir, "nodule_measurement.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved to: {mrk_path}")

if measurements:
    # Save summary
    summary_path = os.path.join(output_dir, "measurement_summary.json")
    with open(summary_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Summary saved to: {summary_path}")
else:
    print("No line measurements found in scene")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_nodule_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_nodule_meas" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_DIAMETER=""
MEASUREMENT_P1=""
MEASUREMENT_P2=""
MEASUREMENT_MIDPOINT=""

# Possible measurement file locations
POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$LIDC_DIR/measurement_summary.json"
    "$LIDC_DIR/Line.mrk.json"
    "/home/ga/Documents/nodule_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        
        # Try to extract measurement data
        MEAS_DATA=$(python3 << PYEOF
import json
import math

with open('$path') as f:
    data = json.load(f)

# Handle different formats
if 'measurements' in data:
    # Summary format
    for m in data['measurements']:
        if m.get('type') == 'line' and m.get('length_mm', 0) > 0:
            print(f"diameter:{m['length_mm']:.2f}")
            print(f"p1:{m.get('p1_ras', [0,0,0])}")
            print(f"p2:{m.get('p2_ras', [0,0,0])}")
            print(f"midpoint:{m.get('midpoint_ras', [0,0,0])}")
            break
elif 'markups' in data:
    # Slicer markup format
    for markup in data['markups']:
        cps = markup.get('controlPoints', [])
        if len(cps) >= 2:
            p1 = cps[0].get('position', [0,0,0])
            p2 = cps[1].get('position', [0,0,0])
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            midpoint = [(a+b)/2 for a,b in zip(p1, p2)]
            print(f"diameter:{length:.2f}")
            print(f"p1:{p1}")
            print(f"p2:{p2}")
            print(f"midpoint:{midpoint}")
            break
PYEOF
2>/dev/null || echo "")

        MEASURED_DIAMETER=$(echo "$MEAS_DATA" | grep "^diameter:" | cut -d: -f2)
        MEASUREMENT_MIDPOINT=$(echo "$MEAS_DATA" | grep "^midpoint:" | cut -d: -f2-)
        
        if [ -n "$MEASURED_DIAMETER" ]; then
            echo "Measured diameter: $MEASURED_DIAMETER mm"
            break
        fi
    fi
done

# Copy measurement to expected location if found elsewhere
if [ "$MEASUREMENT_EXISTS" = "true" ] && [ "$MEASUREMENT_PATH" != "$OUTPUT_MEASUREMENT" ]; then
    cp "$MEASUREMENT_PATH" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
fi

# Check for report file
REPORT_EXISTS="false"
REPORTED_DIAMETER=""
REPORTED_CATEGORY=""
REPORTED_RECOMMENDATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/report.json"
    "/home/ga/Documents/lungrads_report.json"
    "/home/ga/lungrads_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_DIAMETER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('measured_diameter_mm', d.get('diameter_mm', d.get('diameter', ''))))" 2>/dev/null || echo "")
        REPORTED_CATEGORY=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('lungrads_category', d.get('category', '')))" 2>/dev/null || echo "")
        REPORTED_RECOMMENDATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('recommendation', ''))" 2>/dev/null || echo "")
        
        echo "Reported diameter: $REPORTED_DIAMETER mm"
        echo "Reported category: $REPORTED_CATEGORY"
        break
    fi
done

# Check timestamp - was measurement created during task?
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Load ground truth for result file
GT_DIAMETER=""
GT_CATEGORY=""
GT_NODULE_CENTER=""

GT_FILE="$GROUND_TRUTH_DIR/${PATIENT_ID}_nodule_gt.json"
if [ -f "$GT_FILE" ]; then
    GT_DIAMETER=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('ground_truth_diameter_mm', ''))" 2>/dev/null || echo "")
    GT_CATEGORY=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('correct_lungrads_category', ''))" 2>/dev/null || echo "")
    GT_NODULE_CENTER=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('nodule_center_ras', []))" 2>/dev/null || echo "")
    
    # Copy GT for verifier
    cp "$GT_FILE" /tmp/nodule_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/nodule_ground_truth.json 2>/dev/null || true
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measured_diameter_mm": "$MEASURED_DIAMETER",
    "measurement_midpoint_ras": $MEASUREMENT_MIDPOINT,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "reported_diameter_mm": "$REPORTED_DIAMETER",
    "reported_category": "$REPORTED_CATEGORY",
    "reported_recommendation": "$REPORTED_RECOMMENDATION",
    "ground_truth_diameter_mm": "$GT_DIAMETER",
    "ground_truth_category": "$GT_CATEGORY",
    "ground_truth_nodule_center": $GT_NODULE_CENTER,
    "patient_id": "$PATIENT_ID",
    "screenshot_exists": $([ -f "/tmp/lung_nodule_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Fix null values in JSON
sed -i 's/: $/: null/g' "$TEMP_JSON"
sed -i 's/: ""/: null/g' "$TEMP_JSON"
sed -i 's/: ,/: null,/g' "$TEMP_JSON"

# Save result
rm -f /tmp/lung_nodule_result.json 2>/dev/null || sudo rm -f /tmp/lung_nodule_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/lung_nodule_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/lung_nodule_result.json
chmod 666 /tmp/lung_nodule_result.json 2>/dev/null || sudo chmod 666 /tmp/lung_nodule_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/lung_nodule_result.json
echo ""
echo "=== Export Complete ==="