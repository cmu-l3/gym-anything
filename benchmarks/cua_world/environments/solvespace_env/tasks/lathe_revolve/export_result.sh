#!/bin/bash
echo "=== Exporting lathe_revolve task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check for SLVS file
SLVS_PATH="/home/ga/Documents/SolveSpace/stepped_shaft.slvs"
if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c %s "$SLVS_PATH" 2>/dev/null || echo "0")
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED_DURING_TASK="true"
    else
        SLVS_CREATED_DURING_TASK="false"
    fi
else
    SLVS_EXISTS="false"
    SLVS_SIZE="0"
    SLVS_CREATED_DURING_TASK="false"
fi

# Check for STL file
STL_PATH="/home/ga/Documents/SolveSpace/stepped_shaft.stl"
if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c %s "$STL_PATH" 2>/dev/null || echo "0")
    STL_MTIME=$(stat -c %Y "$STL_PATH" 2>/dev/null || echo "0")
    if [ "$STL_MTIME" -gt "$TASK_START" ]; then
        STL_CREATED_DURING_TASK="true"
    else
        STL_CREATED_DURING_TASK="false"
    fi
else
    STL_EXISTS="false"
    STL_SIZE="0"
    STL_CREATED_DURING_TASK="false"
fi

# Check if application was running
APP_RUNNING=$(is_solvespace_running && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "slvs": {
        "exists": $SLVS_EXISTS,
        "size_bytes": $SLVS_SIZE,
        "created_during_task": $SLVS_CREATED_DURING_TASK
    },
    "stl": {
        "exists": $STL_EXISTS,
        "size_bytes": $STL_SIZE,
        "created_during_task": $STL_CREATED_DURING_TASK
    }
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