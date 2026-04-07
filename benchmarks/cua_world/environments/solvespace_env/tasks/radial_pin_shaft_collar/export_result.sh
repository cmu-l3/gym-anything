#!/bin/bash
echo "=== Exporting radial_pin_shaft_collar task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing anything
take_screenshot /tmp/task_final.png

WORKSPACE="/home/ga/Documents/SolveSpace"
SLVS_FILE="$WORKSPACE/radial_collar.slvs"
STL_FILE="$WORKSPACE/radial_collar.stl"

# Check SLVS file
SLVS_EXISTS="false"
SLVS_SIZE="0"
SLVS_CREATED_DURING_TASK="false"

if [ -f "$SLVS_FILE" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c %s "$SLVS_FILE" 2>/dev/null || echo "0")
    SLVS_MTIME=$(stat -c %Y "$SLVS_FILE" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -ge "$TASK_START" ]; then
        SLVS_CREATED_DURING_TASK="true"
    fi
fi

# Check STL file
STL_EXISTS="false"
STL_SIZE="0"
STL_CREATED_DURING_TASK="false"

if [ -f "$STL_FILE" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c %s "$STL_FILE" 2>/dev/null || echo "0")
    STL_MTIME=$(stat -c %Y "$STL_FILE" 2>/dev/null || echo "0")
    if [ "$STL_MTIME" -ge "$TASK_START" ]; then
        STL_CREATED_DURING_TASK="true"
    fi
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

# Close SolveSpace safely
kill_solvespace

echo "=== Export complete ==="