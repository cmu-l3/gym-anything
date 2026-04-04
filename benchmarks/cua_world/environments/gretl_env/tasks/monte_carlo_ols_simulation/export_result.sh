#!/bin/bash
echo "=== Exporting Monte Carlo OLS Simulation results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_DIR="/home/ga/Documents/gretl_output"
SCRIPT_FILE="$OUTPUT_DIR/monte_carlo.inp"
RESULTS_FILE="$OUTPUT_DIR/monte_carlo_results.txt"

# 1. Check Script File
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

# 2. Check Results File
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

# 3. Check App State
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "script_size_bytes": $SCRIPT_SIZE,
    "results_exists": $RESULTS_EXISTS,
    "results_created_during_task": $RESULTS_CREATED_DURING_TASK,
    "results_size_bytes": $RESULTS_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="