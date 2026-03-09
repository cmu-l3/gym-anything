#!/bin/bash
echo "=== Exporting Adrenal Incidentaloma Result ==="

source /workspace/scripts/task_utils.sh

ADRENAL_DIR="/home/ga/Documents/SlicerData/Adrenal"
OUTPUT_MEASUREMENT="$ADRENAL_DIR/nodule_measurement.mrk.json"
OUTPUT_ROI="$ADRENAL_DIR/density_roi.mrk.json"
OUTPUT_REPORT="$ADRENAL_DIR/adrenal_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/adrenal_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any markups from Slicer
    cat > /tmp/export_adrenal_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Adrenal"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Export line/ruler markups (for diameter measurement)
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
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        
        # Save this node
        mrk_path = os.path.join(output_dir, "nodule_measurement.mrk.json")
        slicer.util.saveNode(node, mrk_path)

# Export ROI markups (for density measurement)
roi_classes = [
    "vtkMRMLMarkupsROINode",
    "vtkMRMLMarkupsFiducialNode",
    "vtkMRMLMarkupsCurveNode",
    "vtkMRMLMarkupsClosedCurveNode"
]

for roi_class in roi_classes:
    roi_nodes = slicer.util.getNodesByClass(roi_class)
    for node in roi_nodes:
        n_points = node.GetNumberOfControlPoints()
        if n_points > 0:
            positions = []
            for i in range(n_points):
                pos = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(i, pos)
                positions.append(pos)
            
            roi_data = {
                "name": node.GetName(),
                "type": roi_class.replace("vtkMRMLMarkups", "").replace("Node", "").lower(),
                "n_points": n_points,
                "positions": positions
            }
            all_measurements.append(roi_data)
            print(f"  ROI '{node.GetName()}': {n_points} points")
            
            # Save ROI
            roi_path = os.path.join(output_dir, "density_roi.mrk.json")
            slicer.util.saveNode(node, roi_path)

# Save combined measurements
if all_measurements:
    combined_path = os.path.join(output_dir, "all_markups.json")
    with open(combined_path, "w") as f:
        json.dump({"markups": all_measurements}, f, indent=2)
    print(f"Saved {len(all_measurements)} markups")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_adrenal_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_adrenal_markups" 2>/dev/null || true
fi

# Check for measurement files
MEASUREMENT_EXISTS="false"
MEASURED_DIAMETER=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$ADRENAL_DIR/measurement.mrk.json"
    "$ADRENAL_DIR/ruler.mrk.json"
    "$ADRENAL_DIR/diameter.mrk.json"
    "$ADRENAL_DIR/all_markups.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        echo "Found measurement at: $path"
        
        # Extract diameter
        MEASURED_DIAMETER=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    # Check for line measurements
    if 'markups' in data:
        for m in data['markups']:
            if m.get('type') == 'line' and m.get('length_mm', 0) > 0:
                print(f\"{m['length_mm']:.2f}\")
                break
    elif 'markup' in data:
        # Slicer's native format
        for cp in data.get('markups', [{}])[0].get('controlPoints', []):
            pass
        # Try to calculate from control points
        import math
        cps = data.get('markups', [{}])[0].get('controlPoints', [])
        if len(cps) >= 2:
            p1 = cps[0].get('position', [0,0,0])
            p2 = cps[1].get('position', [0,0,0])
            dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            print(f'{dist:.2f}')
except Exception as e:
    print('')
" 2>/dev/null || echo "")
        break
    fi
done

# Check for ROI/density file
ROI_EXISTS="false"
if [ -f "$OUTPUT_ROI" ] || [ -f "$ADRENAL_DIR/density_roi.mrk.json" ] || [ -f "$ADRENAL_DIR/roi.mrk.json" ]; then
    ROI_EXISTS="true"
fi

# Check for agent's report
REPORT_EXISTS="false"
REPORTED_LATERALITY=""
REPORTED_SIZE=""
REPORTED_HU=""
REPORTED_CLASSIFICATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$ADRENAL_DIR/report.json"
    "$ADRENAL_DIR/findings.json"
    "/home/ga/Documents/adrenal_report.json"
    "/home/ga/adrenal_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract fields
        REPORTED_LATERALITY=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('laterality', ''))" 2>/dev/null || echo "")
        REPORTED_SIZE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('size_mm', d.get('diameter_mm', d.get('diameter', ''))))" 2>/dev/null || echo "")
        REPORTED_HU=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('density_hu', d.get('hu', d.get('density', ''))))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', ''))" 2>/dev/null || echo "")
        
        echo "Report contents:"
        echo "  Laterality: $REPORTED_LATERALITY"
        echo "  Size: $REPORTED_SIZE mm"
        echo "  HU: $REPORTED_HU"
        echo "  Classification: $REPORTED_CLASSIFICATION"
        break
    fi
done

# Check file timestamps for anti-gaming
MEASUREMENT_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    MEAS_MTIME=$(stat -c %Y "$OUTPUT_MEASUREMENT" 2>/dev/null || echo "0")
    if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
        MEASUREMENT_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth to accessible location
cp "$GROUND_TRUTH_DIR/adrenal_gt.json" /tmp/adrenal_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/adrenal_ground_truth.json 2>/dev/null || true

# Copy agent's report
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_adrenal_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_adrenal_report.json 2>/dev/null || true
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
    "measurement_created_during_task": $MEASUREMENT_CREATED_DURING_TASK,
    "measured_diameter_mm": "$MEASURED_DIAMETER",
    "roi_exists": $ROI_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_laterality": "$REPORTED_LATERALITY",
    "reported_size_mm": "$REPORTED_SIZE",
    "reported_hu": "$REPORTED_HU",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "screenshot_exists": $([ -f "/tmp/adrenal_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/adrenal_ground_truth.json" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/adrenal_task_result.json 2>/dev/null || sudo rm -f /tmp/adrenal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/adrenal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/adrenal_task_result.json
chmod 666 /tmp/adrenal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/adrenal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/adrenal_task_result.json
echo ""
echo "=== Export Complete ==="