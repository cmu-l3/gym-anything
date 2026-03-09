#!/bin/bash
echo "=== Exporting Pancreas Size Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/pancreas_measurements.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/pancreas_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/pancreas_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer before closing
    cat > /tmp/export_pancreas_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Check for line/ruler markups (used for diameter measurement)
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
        print(f"  Line '{node.GetName()}': {length:.1f} mm")

# Also check ruler measurements
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
        }
        all_measurements.append(measurement)
        print(f"  Ruler '{node.GetName()}': {length:.1f} mm")

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "pancreas_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also save individual markup nodes
    for node in list(line_nodes) + list(ruler_nodes):
        node_name = node.GetName().replace(" ", "_").replace("/", "_")
        mrk_path = os.path.join(output_dir, f"{node_name}.mrk.json")
        try:
            slicer.util.saveNode(node, mrk_path)
        except:
            pass
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer (briefly)
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_pancreas_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_pancreas_meas" 2>/dev/null || true
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASUREMENT_COUNT=0

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/pancreas_measurements.mrk.json"
    "$AMOS_DIR/measurements.mrk.json"
    "/home/ga/Documents/pancreas_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        # Check if created during task
        MEAS_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MEAS_MTIME" -gt "$TASK_START" ]; then
            echo "  Measurement created during task"
        fi
        # Count measurements
        MEASUREMENT_COUNT=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
measurements = data.get('measurements', [])
print(len(measurements))
" 2>/dev/null || echo "0")
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_HEAD=""
REPORTED_BODY=""
REPORTED_TAIL=""
REPORTED_CLASSIFICATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/pancreas_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/pancreas_report.json"
    "/home/ga/pancreas_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        # Check if created during task
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            echo "  Report created during task"
        fi
        # Extract report fields
        REPORTED_HEAD=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('head_ap_mm', d.get('head', '')))" 2>/dev/null || echo "")
        REPORTED_BODY=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('body_ap_mm', d.get('body', '')))" 2>/dev/null || echo "")
        REPORTED_TAIL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('tail_ap_mm', d.get('tail', '')))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('atrophy_classification', d.get('classification', '')))" 2>/dev/null || echo "")
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Try to extract measurements from the measurement file if report doesn't have them
if [ "$MEASUREMENT_EXISTS" = "true" ] && [ -z "$REPORTED_HEAD" ]; then
    echo "Attempting to extract measurements from markup file..."
    python3 << PYEOF
import json
import os

meas_path = "$MEASUREMENT_PATH"
report_path = "$OUTPUT_REPORT"

try:
    with open(meas_path) as f:
        data = json.load(f)
    
    measurements = data.get('measurements', [])
    
    # Try to identify head/body/tail from measurement names or positions
    head_mm = None
    body_mm = None
    tail_mm = None
    
    for m in measurements:
        name = m.get('name', '').lower()
        length = m.get('length_mm', 0)
        
        if 'head' in name:
            head_mm = length
        elif 'body' in name:
            body_mm = length
        elif 'tail' in name:
            tail_mm = length
    
    # If names don't identify, assume order is head, body, tail
    if len(measurements) >= 3 and (head_mm is None or body_mm is None or tail_mm is None):
        # Sort by x-position (rightmost = head, leftmost = tail)
        sorted_meas = sorted(measurements, key=lambda m: m.get('p1', [0,0,0])[0], reverse=True)
        if head_mm is None:
            head_mm = sorted_meas[0].get('length_mm', 0)
        if body_mm is None:
            body_mm = sorted_meas[1].get('length_mm', 0) if len(sorted_meas) > 1 else 0
        if tail_mm is None:
            tail_mm = sorted_meas[2].get('length_mm', 0) if len(sorted_meas) > 2 else 0
    
    # Save extracted values
    if head_mm is not None or body_mm is not None or tail_mm is not None:
        report = {
            "head_ap_mm": round(head_mm, 1) if head_mm else None,
            "body_ap_mm": round(body_mm, 1) if body_mm else None,
            "tail_ap_mm": round(tail_mm, 1) if tail_mm else None,
            "extracted_from_measurements": True
        }
        
        # If report exists, update it; otherwise create
        if os.path.exists(report_path):
            with open(report_path) as f:
                existing = json.load(f)
            report.update(existing)
        
        with open(report_path, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"Extracted: head={head_mm}, body={body_mm}, tail={tail_mm}")
except Exception as e:
    print(f"Extraction failed: {e}")
PYEOF
fi

# Reload extracted values if updated
if [ -f "$OUTPUT_REPORT" ]; then
    REPORTED_HEAD=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('head_ap_mm', ''))" 2>/dev/null || echo "")
    REPORTED_BODY=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('body_ap_mm', ''))" 2>/dev/null || echo "")
    REPORTED_TAIL=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('tail_ap_mm', ''))" 2>/dev/null || echo "")
fi

# Copy ground truth for verification
echo "Copying ground truth for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_pancreas_gt.json" /tmp/pancreas_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/pancreas_ground_truth.json 2>/dev/null || true

# Copy agent outputs for verification
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_pancreas_measurements.json 2>/dev/null || true
    chmod 644 /tmp/agent_pancreas_measurements.json 2>/dev/null || true
fi
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_pancreas_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_pancreas_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measurement_count": $MEASUREMENT_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_head_mm": "$REPORTED_HEAD",
    "reported_body_mm": "$REPORTED_BODY",
    "reported_tail_mm": "$REPORTED_TAIL",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "screenshot_exists": $([ -f "/tmp/pancreas_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/pancreas_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/pancreas_task_result.json 2>/dev/null || sudo rm -f /tmp/pancreas_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pancreas_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pancreas_task_result.json
chmod 666 /tmp/pancreas_task_result.json 2>/dev/null || sudo chmod 666 /tmp/pancreas_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/pancreas_task_result.json
echo ""
echo "=== Export Complete ==="