#!/bin/bash
set -e
echo "=== Exporting MLE Regression Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCRIPT_PATH="/home/ga/Documents/gretl_output/mle_food.inp"
RESULTS_PATH="/home/ga/Documents/gretl_output/mle_results.txt"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Script File
SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
SCRIPT_SIZE=0
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c %s "$SCRIPT_PATH")
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$SCRIPT_MTIME" -ge "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Results File
RESULTS_EXISTS="false"
RESULTS_CREATED_DURING_TASK="false"
RESULTS_SIZE=0
if [ -f "$RESULTS_PATH" ]; then
    RESULTS_EXISTS="true"
    RESULTS_SIZE=$(stat -c %s "$RESULTS_PATH")
    RESULTS_MTIME=$(stat -c %Y "$RESULTS_PATH")
    if [ "$RESULTS_MTIME" -ge "$TASK_START" ]; then
        RESULTS_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check if Gretl is still running
APP_RUNNING="false"
if pgrep -f "gretl" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
# We use a temp file to avoid permission issues, then move it
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "script_size": $SCRIPT_SIZE,
    "results_exists": $RESULTS_EXISTS,
    "results_created_during_task": $RESULTS_CREATED_DURING_TASK,
    "results_size": $RESULTS_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (accessible to verifier)
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"