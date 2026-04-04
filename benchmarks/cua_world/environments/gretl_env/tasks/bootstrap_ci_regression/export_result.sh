#!/bin/bash
set -euo pipefail

echo "=== Exporting bootstrap_ci_regression results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Define Expected Paths
RESULTS_FILE="/home/ga/Documents/gretl_output/bootstrap_results.txt"
SCRIPT_FILE="/home/ga/Documents/gretl_output/bootstrap_inference.inp"

# Check Results File
RESULTS_EXISTS="false"
RESULTS_CREATED_DURING_TASK="false"
RESULTS_SIZE="0"

if [ -f "$RESULTS_FILE" ]; then
    RESULTS_EXISTS="true"
    RESULTS_MTIME=$(stat -c %Y "$RESULTS_FILE" 2>/dev/null || echo "0")
    RESULTS_SIZE=$(stat -c %s "$RESULTS_FILE" 2>/dev/null || echo "0")
    if [ "$RESULTS_MTIME" -gt "$TASK_START" ]; then
        RESULTS_CREATED_DURING_TASK="true"
    fi
fi

# Check Script File
SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
SCRIPT_SIZE="0"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    SCRIPT_SIZE=$(stat -c %s "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
fi

# Check if Gretl is still running
APP_RUNNING="false"
if pgrep -f "gretl" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON summary
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "results_file_exists": $RESULTS_EXISTS,
    "results_created_during_task": $RESULTS_CREATED_DURING_TASK,
    "results_size_bytes": $RESULTS_SIZE,
    "script_file_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "script_size_bytes": $SCRIPT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Summary exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="