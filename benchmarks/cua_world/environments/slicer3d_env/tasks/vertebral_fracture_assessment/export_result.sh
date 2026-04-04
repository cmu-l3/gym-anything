#!/bin/bash
echo "=== Exporting Vertebral Fracture Assessment Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

SPINE_DIR="/home/ga/Documents/SlicerData/Spine"
OUTPUT_MEASUREMENT="$SPINE_DIR/vertebral_measurements.mrk.json"
OUTPUT_REPORT="$SPINE_DIR/fracture_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task start time for anti-gaming check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/spine_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any measurements from Slicer before checking files
    cat > /tmp/export_spine_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Spine"
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
    meas_path = os.path.join(output_dir, "vertebral_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No line measurements found in scene")

print("Export complete")
PYEOF

    # Run export script in background
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_spine_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_spine_meas" 2>/dev/null || true
fi

# ============================================================
# Check for measurement file
# ============================================================
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASUREMENT_AFTER_START="false"
MEASUREMENT_COUNT=0
MEASURED_LENGTHS=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$SPINE_DIR/measurements.mrk.json"
    "$SPINE_DIR/ruler.mrk.json"
    "/home/ga/Documents/vertebral_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        
        # Check timestamp
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            MEASUREMENT_AFTER_START="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Extract measurement info
        MEASUREMENT_COUNT=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurements', [])
print(len(meas))
" 2>/dev/null || echo "0")
        
        MEASURED_LENGTHS=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
meas = data.get('measurements', [])
lengths = [str(round(m.get('length_mm', 0), 1)) for m in meas if m.get('type') == 'line']
print(','.join(lengths[:5]))
" 2>/dev/null || echo "")
        
        echo "Found measurements at: $path"
        echo "  Count: $MEASUREMENT_COUNT"
        echo "  Lengths: $MEASURED_LENGTHS mm"
        break
    fi
done

# ============================================================
# Check for report file
# ============================================================
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_AFTER_START="false"
REPORT_VALID="false"
AGENT_LEVEL=""
AGENT_HA=""
AGENT_HP=""
AGENT_RATIO=""
AGENT_GRADE=""
AGENT_MORPHOLOGY=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$SPINE_DIR/report.json"
    "$SPINE_DIR/fracture.json"
    "/home/ga/Documents/fracture_report.json"
    "/home/ga/fracture_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        
        # Check timestamp
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            REPORT_AFTER_START="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Parse and validate report
        REPORT_OUTPUT=$(python3 << PYEOF
import json
import os
try:
    with open('$path') as f:
        report = json.load(f)
    
    required = ["vertebral_level", "anterior_height_mm", "posterior_height_mm", 
                "compression_ratio", "genant_grade"]
    
    if all(k in report for k in required):
        print("VALID")
        print(f"LEVEL={report.get('vertebral_level', '')}")
        print(f"HA={report.get('anterior_height_mm', '')}")
        print(f"HP={report.get('posterior_height_mm', '')}")
        print(f"RATIO={report.get('compression_ratio', '')}")
        print(f"GRADE={report.get('genant_grade', '')}")
        print(f"MORPHOLOGY={report.get('morphology', 'unknown')}")
    else:
        missing = [k for k in required if k not in report]
        print(f"INVALID:missing={','.join(missing)}")
except Exception as e:
    print(f"INVALID:error={str(e)}")
PYEOF
)
        
        if echo "$REPORT_OUTPUT" | grep -q "^VALID"; then
            REPORT_VALID="true"
            AGENT_LEVEL=$(echo "$REPORT_OUTPUT" | grep "^LEVEL=" | cut -d= -f2)
            AGENT_HA=$(echo "$REPORT_OUTPUT" | grep "^HA=" | cut -d= -f2)
            AGENT_HP=$(echo "$REPORT_OUTPUT" | grep "^HP=" | cut -d= -f2)
            AGENT_RATIO=$(echo "$REPORT_OUTPUT" | grep "^RATIO=" | cut -d= -f2)
            AGENT_GRADE=$(echo "$REPORT_OUTPUT" | grep "^GRADE=" | cut -d= -f2)
            AGENT_MORPHOLOGY=$(echo "$REPORT_OUTPUT" | grep "^MORPHOLOGY=" | cut -d= -f2)
        fi
        
        echo "Found report at: $path"
        echo "  Valid: $REPORT_VALID"
        echo "  Level: $AGENT_LEVEL, Ha: $AGENT_HA, Hp: $AGENT_HP"
        break
    fi
done

# ============================================================
# Load ground truth
# ============================================================
GT_FILE="$GROUND_TRUTH_DIR/spine_fracture_gt.json"
GT_LEVEL=""
GT_HA=""
GT_HP=""
GT_RATIO=""
GT_GRADE=""
GT_MORPHOLOGY=""

if [ -f "$GT_FILE" ]; then
    GT_LEVEL=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('vertebral_level', ''))" 2>/dev/null || echo "")
    GT_HA=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('anterior_height_mm', ''))" 2>/dev/null || echo "")
    GT_HP=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('posterior_height_mm', ''))" 2>/dev/null || echo "")
    GT_RATIO=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('compression_ratio', ''))" 2>/dev/null || echo "")
    GT_GRADE=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('genant_grade', ''))" 2>/dev/null || echo "")
    GT_MORPHOLOGY=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('morphology', ''))" 2>/dev/null || echo "")
    
    # Copy ground truth for verifier access
    cp "$GT_FILE" /tmp/spine_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/spine_ground_truth.json 2>/dev/null || true
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_after_start": $MEASUREMENT_AFTER_START,
    "measurement_count": $MEASUREMENT_COUNT,
    "measured_lengths": "$MEASURED_LENGTHS",
    "report_exists": $REPORT_EXISTS,
    "report_after_start": $REPORT_AFTER_START,
    "report_valid": $REPORT_VALID,
    "agent_level": "$AGENT_LEVEL",
    "agent_anterior_height": "$AGENT_HA",
    "agent_posterior_height": "$AGENT_HP",
    "agent_ratio": "$AGENT_RATIO",
    "agent_grade": "$AGENT_GRADE",
    "agent_morphology": "$AGENT_MORPHOLOGY",
    "gt_level": "$GT_LEVEL",
    "gt_anterior_height": "$GT_HA",
    "gt_posterior_height": "$GT_HP",
    "gt_ratio": "$GT_RATIO",
    "gt_grade": "$GT_GRADE",
    "gt_morphology": "$GT_MORPHOLOGY",
    "screenshot_path": "/tmp/spine_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/vertebral_task_result.json 2>/dev/null || sudo rm -f /tmp/vertebral_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/vertebral_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/vertebral_task_result.json
chmod 666 /tmp/vertebral_task_result.json 2>/dev/null || sudo chmod 666 /tmp/vertebral_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/vertebral_task_result.json
echo ""
echo "=== Export Complete ==="