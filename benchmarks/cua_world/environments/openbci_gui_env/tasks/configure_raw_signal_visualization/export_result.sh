#!/bin/bash
echo "=== Exporting Raw Signal Visualization Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# 1. Locate Evidence
# ============================================================

# The task description asks for a specific filename, but we check common variations
EXPECTED_PATH="/home/ga/Documents/OpenBCI_GUI/Screenshots/raw_signal_view.png"
ACTUAL_PATH=""

if [ -f "$EXPECTED_PATH" ]; then
    ACTUAL_PATH="$EXPECTED_PATH"
elif [ -f "/home/ga/Documents/OpenBCI_GUI/Recordings/raw_signal_view.png" ]; then
    # Description mentions Recordings folder in one place and Screenshots in another 
    # (common user confusion), so we check both.
    ACTUAL_PATH="/home/ga/Documents/OpenBCI_GUI/Recordings/raw_signal_view.png"
fi

# Check file stats
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -n "$ACTUAL_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ACTUAL_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$ACTUAL_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# ============================================================
# 2. Capture Final Application State
# ============================================================
# Take a system-level screenshot of the final state (independent of agent's screenshot)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if app is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# ============================================================
# 3. Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $FILE_EXISTS,
    "screenshot_path": "$ACTUAL_PATH",
    "screenshot_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "final_state_screenshot": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"