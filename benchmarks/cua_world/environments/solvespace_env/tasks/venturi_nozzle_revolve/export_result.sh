#!/bin/bash
echo "=== Exporting venturi_nozzle_revolve result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

SLVS_PATH="/home/ga/Documents/SolveSpace/venturi_nozzle.slvs"
STEP_PATH="/home/ga/Documents/SolveSpace/venturi_nozzle.step"

SLVS_EXISTS="false"
SLVS_SIZE="0"
SLVS_CREATED_DURING_TASK="false"

STEP_EXISTS="false"
STEP_SIZE="0"
STEP_CREATED_DURING_TASK="false"

if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c%s "$SLVS_PATH" 2>/dev/null || echo "0")
    SLVS_MTIME=$(stat -c%Y "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$STEP_PATH" ]; then
    STEP_EXISTS="true"
    STEP_SIZE=$(stat -c%s "$STEP_PATH" 2>/dev/null || echo "0")
    STEP_MTIME=$(stat -c%Y "$STEP_PATH" 2>/dev/null || echo "0")
    if [ "$STEP_MTIME" -gt "$TASK_START" ]; then
        STEP_CREATED_DURING_TASK="true"
    fi
fi

# Check if SolveSpace was running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_size_bytes": $SLVS_SIZE,
    "slvs_created_during_task": $SLVS_CREATED_DURING_TASK,
    "step_exists": $STEP_EXISTS,
    "step_size_bytes": $STEP_SIZE,
    "step_created_during_task": $STEP_CREATED_DURING_TASK
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="