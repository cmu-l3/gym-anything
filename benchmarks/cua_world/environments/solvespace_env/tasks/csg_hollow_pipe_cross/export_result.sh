#!/bin/bash
echo "=== Exporting CSG Hollow Pipe Cross task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
SLVS_PATH="/home/ga/Documents/SolveSpace/pipe_cross_fitting.slvs"
STL_PATH="/home/ga/Documents/SolveSpace/pipe_cross_fitting.stl"

# Check SLVS file
SLVS_EXISTS="false"
SLVS_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c %s "$SLVS_PATH" 2>/dev/null || echo "0")
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check STL file
STL_EXISTS="false"
STL_SIZE="0"
if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c %s "$STL_PATH" 2>/dev/null || echo "0")
fi

# Check if application was running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "stl_exists": $STL_EXISTS,
    "slvs_size_bytes": $SLVS_SIZE,
    "stl_size_bytes": $STL_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
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