#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SLVS_PATH="/home/ga/Documents/SolveSpace/keyed_hub.slvs"
STL_PATH="/home/ga/Documents/SolveSpace/keyed_hub.stl"

# Check SLVS file
if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED_DURING_TASK="true"
    else
        SLVS_CREATED_DURING_TASK="false"
    fi
else
    SLVS_EXISTS="false"
    SLVS_CREATED_DURING_TASK="false"
fi

# Check STL file
if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_MTIME=$(stat -c %Y "$STL_PATH" 2>/dev/null || echo "0")
    if [ "$STL_MTIME" -gt "$TASK_START" ]; then
        STL_CREATED_DURING_TASK="true"
    else
        STL_CREATED_DURING_TASK="false"
    fi
    STL_SIZE=$(stat -c %s "$STL_PATH" 2>/dev/null || echo "0")
else
    STL_EXISTS="false"
    STL_CREATED_DURING_TASK="false"
    STL_SIZE="0"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_created_during_task": $SLVS_CREATED_DURING_TASK,
    "stl_exists": $STL_EXISTS,
    "stl_created_during_task": $STL_CREATED_DURING_TASK,
    "stl_size_bytes": $STL_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="