#!/bin/bash
set -e
echo "=== Exporting ols_forecast_intervals results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Paths
SCRIPT_PATH="/home/ga/Documents/gretl_output/forecast_script.inp"
RESULTS_PATH="/home/ga/Documents/gretl_output/forecast_results.txt"
GT_PATH="/var/lib/gretl_ground_truth.json"

# Capture final screenshot
take_screenshot /tmp/task_evidence/final_state.png

# Check files
SCRIPT_EXISTS="false"
SCRIPT_CONTENT=""
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    # Read content, escape quotes for JSON
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    # Check timestamp
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_NEW="true"
    else
        SCRIPT_NEW="false"
    fi
else
    SCRIPT_NEW="false"
    SCRIPT_CONTENT="\"\""
fi

RESULTS_EXISTS="false"
RESULTS_CONTENT=""
if [ -f "$RESULTS_PATH" ]; then
    RESULTS_EXISTS="true"
    RESULTS_CONTENT=$(cat "$RESULTS_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    RESULTS_MTIME=$(stat -c %Y "$RESULTS_PATH")
    if [ "$RESULTS_MTIME" -gt "$TASK_START" ]; then
        RESULTS_NEW="true"
    else
        RESULTS_NEW="false"
    fi
else
    RESULTS_NEW="false"
    RESULTS_CONTENT="\"\""
fi

# Load Ground Truth
GT_CONTENT="{}"
if [ -f "$GT_PATH" ]; then
    GT_CONTENT=$(cat "$GT_PATH")
fi

# Application state
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_new": $SCRIPT_NEW,
    "script_content": $SCRIPT_CONTENT,
    "results_exists": $RESULTS_EXISTS,
    "results_new": $RESULTS_NEW,
    "results_content": $RESULTS_CONTENT,
    "ground_truth": $GT_CONTENT,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_evidence/final_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"