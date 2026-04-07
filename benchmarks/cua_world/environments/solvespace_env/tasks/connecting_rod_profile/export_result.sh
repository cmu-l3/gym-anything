#!/bin/bash
echo "=== Exporting connecting_rod_profile task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SLVS_PATH="/home/ga/Documents/SolveSpace/connecting_rod.slvs"
STL_PATH="/home/ga/Documents/SolveSpace/connecting_rod.stl"

# Check SLVS file attributes
if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    SLVS_SIZE=$(stat -c %s "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED="true"
    else
        SLVS_CREATED="false"
    fi
else
    SLVS_EXISTS="false"
    SLVS_CREATED="false"
    SLVS_SIZE="0"
fi

# Check STL file attributes
if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_MTIME=$(stat -c %Y "$STL_PATH" 2>/dev/null || echo "0")
    STL_SIZE=$(stat -c %s "$STL_PATH" 2>/dev/null || echo "0")
    if [ "$STL_MTIME" -gt "$TASK_START" ]; then
        STL_CREATED="true"
    else
        STL_CREATED="false"
    fi
else
    STL_EXISTS="false"
    STL_CREATED="false"
    STL_SIZE="0"
fi

# Check if SolveSpace was running
APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_created_during_task": $SLVS_CREATED,
    "slvs_size_bytes": $SLVS_SIZE,
    "stl_exists": $STL_EXISTS,
    "stl_created_during_task": $STL_CREATED,
    "stl_size_bytes": $STL_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move file into place securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="