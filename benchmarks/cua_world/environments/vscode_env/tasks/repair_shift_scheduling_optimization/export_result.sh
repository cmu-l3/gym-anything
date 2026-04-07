#!/bin/bash
echo "=== Exporting Shift Scheduling Task Results ==="

WORKSPACE_DIR="/home/ga/workspace/nurse_scheduling"
RESULT_FILE="/tmp/task_result.json"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Focus VSCode and attempt to save all open files to capture latest work
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key ctrl+shift+s 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Check if application was running
APP_RUNNING=$(pgrep -f "code.*--ms-enable-electron" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Collect schedule.csv and schedule_model.py
CSV_CONTENT=""
CSV_MODIFIED="false"
if [ -f "$WORKSPACE_DIR/schedule.csv" ]; then
    CSV_MTIME=$(stat -c %Y "$WORKSPACE_DIR/schedule.csv" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
    # Use python to safely encode file content to json string
    CSV_CONTENT=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' < "$WORKSPACE_DIR/schedule.csv")
else
    CSV_CONTENT="null"
fi

PY_CONTENT=""
if [ -f "$WORKSPACE_DIR/schedule_model.py" ]; then
    PY_CONTENT=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' < "$WORKSPACE_DIR/schedule_model.py")
else
    PY_CONTENT="null"
fi

# Create JSON result
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "csv_modified_during_task": $CSV_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "schedule_csv": $CSV_CONTENT,
    "schedule_model_py": $PY_CONTENT
}
EOF

chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
echo "=== Export complete ==="