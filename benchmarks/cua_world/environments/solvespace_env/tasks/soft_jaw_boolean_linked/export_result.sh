#!/bin/bash
echo "=== Exporting soft_jaw_boolean_linked result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

SLVS_PATH="/home/ga/Documents/SolveSpace/soft_jaw_fixture.slvs"
STEP_PATH="/home/ga/Documents/SolveSpace/soft_jaw_fixture.step"

SLVS_EXISTS="false"
STEP_EXISTS="false"
SLVS_CREATED="false"
STEP_CREATED="false"
SLVS_SIZE="0"
STEP_SIZE="0"

# Check SLVS file
if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c%s "$SLVS_PATH" 2>/dev/null || echo "0")
    SLVS_MTIME=$(stat -c%Y "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED="true"
    fi
    # Copy to /tmp/ for verifier
    cp "$SLVS_PATH" /tmp/soft_jaw_fixture.slvs
    chmod 666 /tmp/soft_jaw_fixture.slvs
fi

# Check STEP file
if [ -f "$STEP_PATH" ]; then
    STEP_EXISTS="true"
    STEP_SIZE=$(stat -c%s "$STEP_PATH" 2>/dev/null || echo "0")
    STEP_MTIME=$(stat -c%Y "$STEP_PATH" 2>/dev/null || echo "0")
    if [ "$STEP_MTIME" -gt "$TASK_START" ]; then
        STEP_CREATED="true"
    fi
    # Copy to /tmp/ for verifier
    cp "$STEP_PATH" /tmp/soft_jaw_fixture.step
    chmod 666 /tmp/soft_jaw_fixture.step
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "step_exists": $STEP_EXISTS,
    "slvs_created_during_task": $SLVS_CREATED,
    "step_created_during_task": $STEP_CREATED,
    "slvs_size_bytes": $SLVS_SIZE,
    "step_size_bytes": $STEP_SIZE,
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