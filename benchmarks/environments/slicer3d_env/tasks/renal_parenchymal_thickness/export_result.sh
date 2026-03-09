#!/bin/bash
echo "=== Exporting Renal Parenchymal Thickness Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/renal_thickness_measurements.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/renal_parenchyma_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any measurements from Slicer
    cat > /tmp/export_renal_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

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
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm")

# Save measurements if any found
if all_measurements:
    meas_path = os.path.join(output_dir, "renal_thickness_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also try to save the individual markup nodes
    for node in line_nodes:
        try:
            mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
            slicer.util.saveNode(node, mrk_path)
        except:
            pass
else:
    print("No line measurements found in scene")

print("Measurement export complete")
PYEOF

    # Run the export script in Slicer (background, with timeout)
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_renal_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 2
fi

# Check if markup file exists and was created during task
MARKUP_EXISTS="false"
MARKUP_VALID="false"
MARKUP_PATH=""
MEASUREMENT_COUNT=0

POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/renal_thickness_measurements.mrk.json"
    "$AMOS_DIR/measurements.mrk.json"
    "/home/ga/Documents/renal_thickness_measurements.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUP_EXISTS="true"
        MARKUP_PATH="$path"
        
        # Check timestamp
        MARKUP_TIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MARKUP_TIME" -gt "$TASK_START" ]; then
            MARKUP_VALID="true"
        fi
        
        # Count measurements
        MEASUREMENT_COUNT=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    meas = data.get('measurements', [])
    print(len([m for m in meas if m.get('type') == 'line']))
except:
    print(0)
" 2>/dev/null || echo "0")
        
        echo "Found markup at: $path (valid=$MARKUP_VALID, measurements=$MEASUREMENT_COUNT)"
        
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        break
    fi
done

# Check if report file exists and was created during task
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_PATH=""
REPORT_COMPLETE="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/renal_parenchyma_report.json"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/kidney_report.json"
    "/home/ga/Documents/renal_parenchyma_report.json"
    "/home/ga/renal_parenchyma_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        
        # Check timestamp
        REPORT_TIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_TIME" -gt "$TASK_START" ]; then
            REPORT_VALID="true"
        fi
        
        echo "Found report at: $path (valid=$REPORT_VALID)"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Parse the report if it exists
RIGHT_ANTERIOR=""
RIGHT_POSTERIOR=""
RIGHT_LATERAL=""
RIGHT_AVERAGE=""
RIGHT_CLASSIFICATION=""
LEFT_ANTERIOR=""
LEFT_POSTERIOR=""
LEFT_LATERAL=""
LEFT_AVERAGE=""
LEFT_CLASSIFICATION=""
BILATERAL_DIFF=""
SYMMETRY=""

if [ -f "$OUTPUT_REPORT" ]; then
    # Extract values from report JSON
    python3 << PYEOF > /tmp/report_parsed.txt 2>/dev/null || true
import json
try:
    with open("$OUTPUT_REPORT") as f:
        data = json.load(f)
    
    rk = data.get("right_kidney", {})
    lk = data.get("left_kidney", {})
    
    print(f"RIGHT_ANTERIOR={rk.get('anterior_mm', '')}")
    print(f"RIGHT_POSTERIOR={rk.get('posterior_mm', '')}")
    print(f"RIGHT_LATERAL={rk.get('lateral_mm', '')}")
    print(f"RIGHT_AVERAGE={rk.get('average_mm', '')}")
    print(f"RIGHT_CLASSIFICATION={rk.get('classification', '')}")
    print(f"LEFT_ANTERIOR={lk.get('anterior_mm', '')}")
    print(f"LEFT_POSTERIOR={lk.get('posterior_mm', '')}")
    print(f"LEFT_LATERAL={lk.get('lateral_mm', '')}")
    print(f"LEFT_AVERAGE={lk.get('average_mm', '')}")
    print(f"LEFT_CLASSIFICATION={lk.get('classification', '')}")
    print(f"BILATERAL_DIFF={data.get('bilateral_difference_mm', '')}")
    print(f"SYMMETRY={data.get('symmetry_assessment', '')}")
    
    # Check completeness
    complete = all([
        rk.get('anterior_mm'), rk.get('posterior_mm'), rk.get('lateral_mm'),
        rk.get('average_mm'), rk.get('classification'),
        lk.get('anterior_mm'), lk.get('posterior_mm'), lk.get('lateral_mm'),
        lk.get('average_mm'), lk.get('classification'),
        data.get('bilateral_difference_mm') is not None,
        data.get('symmetry_assessment')
    ])
    print(f"REPORT_COMPLETE={'true' if complete else 'false'}")
except Exception as e:
    print(f"ERROR={e}")
PYEOF

    if [ -f /tmp/report_parsed.txt ]; then
        source /tmp/report_parsed.txt 2>/dev/null || true
    fi
fi

# Copy ground truth for verification
echo "Preparing files for verification..."
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_renal_thickness_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/renal_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/renal_ground_truth.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "markup_exists": $MARKUP_EXISTS,
    "markup_valid": $MARKUP_VALID,
    "markup_path": "$MARKUP_PATH",
    "measurement_count": $MEASUREMENT_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_path": "$REPORT_PATH",
    "report_complete": ${REPORT_COMPLETE:-false},
    "agent_values": {
        "right_kidney": {
            "anterior_mm": "$RIGHT_ANTERIOR",
            "posterior_mm": "$RIGHT_POSTERIOR",
            "lateral_mm": "$RIGHT_LATERAL",
            "average_mm": "$RIGHT_AVERAGE",
            "classification": "$RIGHT_CLASSIFICATION"
        },
        "left_kidney": {
            "anterior_mm": "$LEFT_ANTERIOR",
            "posterior_mm": "$LEFT_POSTERIOR",
            "lateral_mm": "$LEFT_LATERAL",
            "average_mm": "$LEFT_AVERAGE",
            "classification": "$LEFT_CLASSIFICATION"
        },
        "bilateral_difference_mm": "$BILATERAL_DIFF",
        "symmetry_assessment": "$SYMMETRY"
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/renal_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/renal_task_result.json 2>/dev/null || sudo rm -f /tmp/renal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/renal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/renal_task_result.json
chmod 666 /tmp/renal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/renal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/renal_task_result.json
echo ""
echo "=== Export Complete ==="