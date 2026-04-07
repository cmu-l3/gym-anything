#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SLVS_PATH="/home/ga/Documents/SolveSpace/countersunk_bolt.slvs"
STL_PATH="/home/ga/Documents/SolveSpace/countersunk_bolt.stl"

# Evaluate SLVS file
SLVS_EXISTS="false"
SLVS_CREATED="false"
SLVS_SIZE="0"
if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c %s "$SLVS_PATH" 2>/dev/null || echo "0")
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED="true"
    fi
fi

# Evaluate STL file
STL_EXISTS="false"
STL_CREATED="false"
STL_SIZE="0"
if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c %s "$STL_PATH" 2>/dev/null || echo "0")
    STL_MTIME=$(stat -c %Y "$STL_PATH" 2>/dev/null || echo "0")
    if [ "$STL_MTIME" -gt "$TASK_START" ]; then
        STL_CREATED="true"
    fi
fi

# Check if SolveSpace was running
APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result object
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "slvs": {
        "exists": $SLVS_EXISTS,
        "created_during_task": $SLVS_CREATED,
        "size_bytes": $SLVS_SIZE
    },
    "stl": {
        "exists": $STL_EXISTS,
        "created_during_task": $STL_CREATED,
        "size_bytes": $STL_SIZE
    }
}
EOF

# Safely copy to standard path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="