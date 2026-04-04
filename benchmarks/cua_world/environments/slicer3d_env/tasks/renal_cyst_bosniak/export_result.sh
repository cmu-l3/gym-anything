#!/bin/bash
echo "=== Exporting Renal Cyst Bosniak Classification Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record export time
EXPORT_TIME=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get case ID
if [ -f /tmp/renal_cyst_case_id ]; then
    CASE_ID=$(cat /tmp/renal_cyst_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GT_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENT="$AMOS_DIR/cyst_measurements.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/bosniak_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true
sleep 1

# Check Slicer status
SLICER_RUNNING="false"
if pgrep -f Slicer > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Initialize result variables
MARKUPS_EXIST="false"
MARKUPS_PATH=""
MARKUPS_SIZE=0
MARKUPS_MTIME=0
MARKUPS_CREATED_DURING_TASK="false"

REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CREATED_DURING_TASK="false"

# Check for measurement file
POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/cyst_measurements.mrk.json"
    "$AMOS_DIR/measurements.mrk.json"
    "$AMOS_DIR/measurement.mrk.json"
    "/home/ga/Documents/cyst_measurements.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUPS_EXIST="true"
        MARKUPS_PATH="$path"
        MARKUPS_SIZE=$(stat -c%s "$path" 2>/dev/null || echo 0)
        MARKUPS_MTIME=$(stat -c%Y "$path" 2>/dev/null || echo 0)
        if [ "$MARKUPS_MTIME" -gt "$TASK_START" ]; then
            MARKUPS_CREATED_DURING_TASK="true"
        fi
        echo "Found measurements at: $path"
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        break
    fi
done

# Check for report file
POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/bosniak_report.json"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/cyst_report.json"
    "/home/ga/Documents/bosniak_report.json"
    "/home/ga/bosniak_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_SIZE=$(stat -c%s "$path" 2>/dev/null || echo 0)
        REPORT_MTIME=$(stat -c%Y "$path" 2>/dev/null || echo 0)
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Extract agent's report data
AGENT_REPORT_JSON="{}"
if [ -f "$OUTPUT_REPORT" ]; then
    AGENT_REPORT_JSON=$(cat "$OUTPUT_REPORT" 2>/dev/null || echo "{}")
fi

# Extract agent's measurements from markup file
AGENT_MEASUREMENTS_JSON="[]"
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    AGENT_MEASUREMENTS_JSON=$(python3 << 'PYEOF'
import json
import sys
try:
    with open("/home/ga/Documents/SlicerData/AMOS/cyst_measurements.mrk.json", "r") as f:
        data = json.load(f)
    # Handle various markup formats
    measurements = []
    if "markups" in data:
        for markup in data["markups"]:
            if "controlPoints" in markup:
                for cp in markup["controlPoints"]:
                    measurements.append({"type": "point", "position": cp.get("position", [])})
            if "measurements" in markup:
                measurements.extend(markup["measurements"])
    elif "controlPoints" in data:
        for cp in data["controlPoints"]:
            measurements.append({"type": "point", "position": cp.get("position", [])})
    elif "measurements" in data:
        measurements = data["measurements"]
    print(json.dumps(measurements))
except Exception as e:
    print("[]")
PYEOF
)
fi

# Copy ground truth for verification
cp "$GT_DIR/${CASE_ID}_cyst_gt.json" /tmp/cyst_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/cyst_ground_truth.json 2>/dev/null || true

# Copy agent files for verification
if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_cyst_measurements.json 2>/dev/null || true
    chmod 644 /tmp/agent_cyst_measurements.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_bosniak_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_bosniak_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "export_time": $EXPORT_TIME,
    "slicer_was_running": $SLICER_RUNNING,
    "markups_exist": $MARKUPS_EXIST,
    "markups_path": "$MARKUPS_PATH",
    "markups_size_bytes": $MARKUPS_SIZE,
    "markups_mtime": $MARKUPS_MTIME,
    "markups_created_during_task": $MARKUPS_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "case_id": "$CASE_ID",
    "ground_truth_available": $([ -f "/tmp/cyst_ground_truth.json" ] && echo "true" || echo "false"),
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "agent_report": $AGENT_REPORT_JSON,
    "agent_measurements": $AGENT_MEASUREMENTS_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="