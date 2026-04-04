#!/bin/bash
echo "=== Exporting Renal Nephrometry Scoring Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

KITS_DIR="/home/ga/Documents/SlicerData/KiTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
RESULT_FILE="/tmp/renal_task_result.json"

# Get case ID
CASE_ID="case_00002"
if [ -f /tmp/kits_case_id ]; then
    CASE_ID=$(cat /tmp/kits_case_id)
fi

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ELAPSED=$((TASK_END - TASK_START))

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null; then
    SLICER_RUNNING="true"
fi

# Check for agent's report file
AGENT_REPORT="$KITS_DIR/renal_score_report.json"
AGENT_MEASUREMENTS="$KITS_DIR/agent_measurements.mrk.json"

REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_MTIME="0"
MEASUREMENTS_EXIST="false"
MEASUREMENTS_MTIME="0"

# Search for report in multiple locations
POSSIBLE_REPORT_PATHS=(
    "$AGENT_REPORT"
    "$KITS_DIR/renal_report.json"
    "$KITS_DIR/report.json"
    "/home/ga/Documents/renal_score_report.json"
    "/home/ga/renal_score_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Copy to expected location if different
        if [ "$path" != "$AGENT_REPORT" ]; then
            cp "$path" "$AGENT_REPORT" 2>/dev/null || true
        fi
        
        # Validate JSON structure
        if python3 -c "import json; json.load(open('$path'))" 2>/dev/null; then
            REPORT_VALID="true"
        fi
        
        echo "Found report at: $path (valid=$REPORT_VALID)"
        break
    fi
done

# Search for measurements
POSSIBLE_MEAS_PATHS=(
    "$AGENT_MEASUREMENTS"
    "$KITS_DIR/measurements.mrk.json"
    "$KITS_DIR/ruler.mrk.json"
    "/home/ga/Documents/agent_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENTS_EXIST="true"
        MEASUREMENTS_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$path" != "$AGENT_MEASUREMENTS" ]; then
            cp "$path" "$AGENT_MEASUREMENTS" 2>/dev/null || true
        fi
        
        echo "Found measurements at: $path"
        break
    fi
done

# Check if files were created during task (anti-gaming)
REPORT_CREATED_DURING_TASK="false"
MEASUREMENTS_CREATED_DURING_TASK="false"

if [ "$REPORT_EXISTS" = "true" ] && [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

if [ "$MEASUREMENTS_EXIST" = "true" ] && [ "$MEASUREMENTS_MTIME" -gt "$TASK_START" ]; then
    MEASUREMENTS_CREATED_DURING_TASK="true"
fi

# Try to extract measurements from Slicer if still running
if [ "$SLICER_RUNNING" = "true" ] && [ "$MEASUREMENTS_EXIST" = "false" ]; then
    echo "Attempting to export measurements from Slicer..."
    
    cat > /tmp/export_renal_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/KiTS"
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

# Save measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "agent_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
else:
    print("No measurements found in scene")
PYEOF

    sudo -u ga DISPLAY=:1 timeout 30 /opt/Slicer/Slicer --python-script /tmp/export_renal_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 5
    
    # Re-check for measurements
    if [ -f "$AGENT_MEASUREMENTS" ]; then
        MEASUREMENTS_EXIST="true"
        MEASUREMENTS_MTIME=$(stat -c %Y "$AGENT_MEASUREMENTS" 2>/dev/null || echo "0")
        if [ "$MEASUREMENTS_MTIME" -gt "$TASK_START" ]; then
            MEASUREMENTS_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Extract key values from agent's report for verification
AGENT_TOTAL_SCORE=""
AGENT_DIAMETER=""
AGENT_COMPLEXITY=""

if [ "$REPORT_VALID" = "true" ]; then
    AGENT_TOTAL_SCORE=$(python3 -c "import json; d=json.load(open('$AGENT_REPORT')); print(d.get('total_score', ''))" 2>/dev/null || echo "")
    AGENT_DIAMETER=$(python3 -c "import json; d=json.load(open('$AGENT_REPORT')); print(d.get('R_diameter_cm', ''))" 2>/dev/null || echo "")
    AGENT_COMPLEXITY=$(python3 -c "import json; d=json.load(open('$AGENT_REPORT')); print(d.get('complexity', ''))" 2>/dev/null || echo "")
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${CASE_ID}_renal_gt.json" /tmp/renal_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/renal_ground_truth.json 2>/dev/null || true

# Copy agent report for verifier
if [ -f "$AGENT_REPORT" ]; then
    cp "$AGENT_REPORT" /tmp/agent_renal_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_renal_report.json 2>/dev/null || true
fi

# Check screenshot exists
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "case_id": "$CASE_ID",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "elapsed_seconds": $ELAPSED,
    "slicer_was_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "measurements_exist": $MEASUREMENTS_EXIST,
    "measurements_created_during_task": $MEASUREMENTS_CREATED_DURING_TASK,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_total_score": "$AGENT_TOTAL_SCORE",
    "agent_diameter_cm": "$AGENT_DIAMETER",
    "agent_complexity": "$AGENT_COMPLEXITY",
    "agent_report_path": "/tmp/agent_renal_report.json",
    "ground_truth_path": "/tmp/renal_ground_truth.json"
}
EOF

# Save result
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="