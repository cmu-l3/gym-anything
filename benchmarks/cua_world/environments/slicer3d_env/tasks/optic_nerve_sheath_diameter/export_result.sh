#!/bin/bash
echo "=== Exporting ONSD Measurement Results ==="

source /workspace/scripts/task_utils.sh

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION} seconds"

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

OUTPUT_RIGHT="$BRATS_DIR/right_onsd.mrk.json"
OUTPUT_LEFT="$BRATS_DIR/left_onsd.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/onsd_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/onsd_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Export any line markups from Slicer before closing
    echo "Exporting measurements from Slicer..."
    cat > /tmp/export_onsd_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Get all line markup nodes
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

measurements = []
for node in line_nodes:
    name = node.GetName().lower()
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
            "center": [(a+b)/2 for a,b in zip(p1, p2)]
        }
        measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        
        # Determine if this is right or left based on name or x-coordinate
        is_right = 'right' in name or 'r_' in name or name.startswith('r')
        is_left = 'left' in name or 'l_' in name or name.startswith('l')
        
        # If not determined by name, use x-coordinate (positive x = patient right in RAS)
        if not is_right and not is_left:
            center_x = (p1[0] + p2[0]) / 2
            is_right = center_x > 0
            is_left = center_x < 0
        
        # Save as appropriate file
        if is_right:
            markup_data = {
                "measurement": measurement,
                "side": "right",
                "onsd_mm": length
            }
            with open(os.path.join(output_dir, "right_onsd.mrk.json"), "w") as f:
                json.dump(markup_data, f, indent=2)
            print(f"    Saved as RIGHT ONSD")
        elif is_left:
            markup_data = {
                "measurement": measurement,
                "side": "left", 
                "onsd_mm": length
            }
            with open(os.path.join(output_dir, "left_onsd.mrk.json"), "w") as f:
                json.dump(markup_data, f, indent=2)
            print(f"    Saved as LEFT ONSD")
        
        # Also save the native Slicer markup file
        slicer.util.saveNode(node, os.path.join(output_dir, f"{node.GetName()}.mrk.json"))

# Save all measurements summary
if measurements:
    with open(os.path.join(output_dir, "all_measurements.json"), "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)

print("Export complete")
PYEOF

    # Run export script with timeout
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_onsd_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Check for right ONSD measurement
RIGHT_EXISTS="false"
RIGHT_ONSD=""
RIGHT_COORDS=""
RIGHT_MTIME="0"

POSSIBLE_RIGHT_PATHS=(
    "$OUTPUT_RIGHT"
    "$BRATS_DIR/Right_ONSD.mrk.json"
    "$BRATS_DIR/right.mrk.json"
    "$BRATS_DIR/R_ONSD.mrk.json"
)

for path in "${POSSIBLE_RIGHT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        RIGHT_EXISTS="true"
        RIGHT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        # Extract ONSD value
        RIGHT_ONSD=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
# Try different possible structures
onsd = data.get('onsd_mm', 0)
if onsd == 0 and 'measurement' in data:
    onsd = data['measurement'].get('length_mm', 0)
if onsd == 0 and 'measurements' in data:
    for m in data['measurements']:
        if m.get('length_mm', 0) > 0:
            onsd = m['length_mm']
            break
print(f'{onsd:.2f}')
" 2>/dev/null || echo "0")
        if [ "$path" != "$OUTPUT_RIGHT" ]; then
            cp "$path" "$OUTPUT_RIGHT" 2>/dev/null || true
        fi
        echo "Found right ONSD: $RIGHT_ONSD mm at $path"
        break
    fi
done

# Check for left ONSD measurement
LEFT_EXISTS="false"
LEFT_ONSD=""
LEFT_COORDS=""
LEFT_MTIME="0"

POSSIBLE_LEFT_PATHS=(
    "$OUTPUT_LEFT"
    "$BRATS_DIR/Left_ONSD.mrk.json"
    "$BRATS_DIR/left.mrk.json"
    "$BRATS_DIR/L_ONSD.mrk.json"
)

for path in "${POSSIBLE_LEFT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LEFT_EXISTS="true"
        LEFT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        # Extract ONSD value
        LEFT_ONSD=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
onsd = data.get('onsd_mm', 0)
if onsd == 0 and 'measurement' in data:
    onsd = data['measurement'].get('length_mm', 0)
if onsd == 0 and 'measurements' in data:
    for m in data['measurements']:
        if m.get('length_mm', 0) > 0:
            onsd = m['length_mm']
            break
print(f'{onsd:.2f}')
" 2>/dev/null || echo "0")
        if [ "$path" != "$OUTPUT_LEFT" ]; then
            cp "$path" "$OUTPUT_LEFT" 2>/dev/null || true
        fi
        echo "Found left ONSD: $LEFT_ONSD mm at $path"
        break
    fi
done

# Check for clinical report
REPORT_EXISTS="false"
REPORTED_RIGHT=""
REPORTED_LEFT=""
REPORTED_MEAN=""
REPORTED_ICP=""
REPORT_MTIME="0"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/clinical_report.json"
    "/home/ga/Documents/onsd_report.json"
    "/home/ga/onsd_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        # Extract report fields
        REPORTED_RIGHT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('right_onsd_mm', ''))" 2>/dev/null || echo "")
        REPORTED_LEFT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('left_onsd_mm', ''))" 2>/dev/null || echo "")
        REPORTED_MEAN=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('mean_onsd_mm', ''))" 2>/dev/null || echo "")
        REPORTED_ICP=$(python3 -c "import json; d=json.load(open('$path')); print(str(d.get('elevated_icp_suspected', '')).lower())" 2>/dev/null || echo "")
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        echo "Found report at: $path"
        break
    fi
done

# Check if files were created during task (anti-gaming)
RIGHT_CREATED_DURING_TASK="false"
LEFT_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ "$RIGHT_EXISTS" = "true" ] && [ "$RIGHT_MTIME" -gt "$TASK_START" ]; then
    RIGHT_CREATED_DURING_TASK="true"
fi
if [ "$LEFT_EXISTS" = "true" ] && [ "$LEFT_MTIME" -gt "$TASK_START" ]; then
    LEFT_CREATED_DURING_TASK="true"
fi
if [ "$REPORT_EXISTS" = "true" ] && [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_onsd_gt.json" /tmp/onsd_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/onsd_ground_truth.json 2>/dev/null || true

# Copy agent outputs for verifier
if [ -f "$OUTPUT_RIGHT" ]; then
    cp "$OUTPUT_RIGHT" /tmp/agent_right_onsd.json 2>/dev/null || true
    chmod 644 /tmp/agent_right_onsd.json 2>/dev/null || true
fi
if [ -f "$OUTPUT_LEFT" ]; then
    cp "$OUTPUT_LEFT" /tmp/agent_left_onsd.json 2>/dev/null || true
    chmod 644 /tmp/agent_left_onsd.json 2>/dev/null || true
fi
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_onsd_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_onsd_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "slicer_was_running": $SLICER_RUNNING,
    "sample_id": "$SAMPLE_ID",
    "right_onsd": {
        "exists": $RIGHT_EXISTS,
        "value_mm": "$RIGHT_ONSD",
        "created_during_task": $RIGHT_CREATED_DURING_TASK
    },
    "left_onsd": {
        "exists": $LEFT_EXISTS,
        "value_mm": "$LEFT_ONSD",
        "created_during_task": $LEFT_CREATED_DURING_TASK
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "right_onsd_mm": "$REPORTED_RIGHT",
        "left_onsd_mm": "$REPORTED_LEFT",
        "mean_onsd_mm": "$REPORTED_MEAN",
        "elevated_icp_suspected": "$REPORTED_ICP"
    },
    "screenshot_exists": $([ -f "/tmp/onsd_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/onsd_ground_truth.json" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/onsd_task_result.json 2>/dev/null || sudo rm -f /tmp/onsd_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/onsd_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/onsd_task_result.json
chmod 666 /tmp/onsd_task_result.json 2>/dev/null || sudo chmod 666 /tmp/onsd_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/onsd_task_result.json
echo ""
echo "=== Export Complete ==="