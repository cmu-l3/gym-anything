#!/bin/bash
echo "=== Exporting eco_profile_extrusion_step task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before altering state
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SLVS_PATH="/home/ga/Documents/SolveSpace/base_4_5mm.slvs"
STEP_PATH="/home/ga/Documents/SolveSpace/base_4_5mm.step"

SLVS_EXISTS="false"
SLVS_CREATED_DURING_TASK="false"
SLVS_SIZE=0

STEP_EXISTS="false"
STEP_CREATED_DURING_TASK="false"
STEP_SIZE=0

# Process the SLVS file
if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c %s "$SLVS_PATH" 2>/dev/null || echo "0")
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED_DURING_TASK="true"
    fi
    
    # Copy to tmp for verifier to extract
    cp "$SLVS_PATH" /tmp/eval_base.slvs
    chmod 666 /tmp/eval_base.slvs
fi

# Process the STEP file
if [ -f "$STEP_PATH" ]; then
    STEP_EXISTS="true"
    STEP_SIZE=$(stat -c %s "$STEP_PATH" 2>/dev/null || echo "0")
    STEP_MTIME=$(stat -c %Y "$STEP_PATH" 2>/dev/null || echo "0")
    
    if [ "$STEP_MTIME" -gt "$TASK_START" ]; then
        STEP_CREATED_DURING_TASK="true"
    fi
    
    # Copy to tmp for verifier to extract
    cp "$STEP_PATH" /tmp/eval_base.step
    chmod 666 /tmp/eval_base.step
fi

# Check if application was running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Generate JSON report
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_was_running": $APP_RUNNING,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_created_during_task": $SLVS_CREATED_DURING_TASK,
    "slvs_size_bytes": $SLVS_SIZE,
    "step_exists": $STEP_EXISTS,
    "step_created_during_task": $STEP_CREATED_DURING_TASK,
    "step_size_bytes": $STEP_SIZE
}
EOF

# Move JSON securely to /tmp
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Task evaluation payload prepared."
cat /tmp/task_result.json
echo "=== Export complete ==="