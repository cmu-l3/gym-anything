#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Gather timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# Target Paths
SCRIPT_PATH="/home/ga/pick_monitor.py"
LOG_PATH="/home/ga/pick_log.txt"
TARGET_ID=$(cat /tmp/target_pick_id.txt 2>/dev/null || echo "")

# Read Python script content safely
SCRIPT_EXISTS="false"
SCRIPT_B64=""
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_B64=$(cat "$SCRIPT_PATH" 2>/dev/null | base64 -w 0)
fi

# Read Log output content safely
LOG_EXISTS="false"
LOG_B64=""
LOG_MTIME=0
if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_B64=$(cat "$LOG_PATH" 2>/dev/null | base64 -w 0)
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
fi

# Check if the python script is still running
APP_RUNNING="false"
if pgrep -f "pick_monitor.py" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON file containing evaluation data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "log_exists": $LOG_EXISTS,
    "log_mtime": $LOG_MTIME,
    "app_was_running": $APP_RUNNING,
    "target_id": "$TARGET_ID",
    "script_b64": "$SCRIPT_B64",
    "log_b64": "$LOG_B64"
}
EOF

# Carefully copy to target destination to avoid any permission collisions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="