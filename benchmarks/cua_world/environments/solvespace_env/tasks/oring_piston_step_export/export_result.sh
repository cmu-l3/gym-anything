#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SLVS_PATH="/home/ga/Documents/SolveSpace/piston_groove.slvs"
STEP_PATH="/home/ga/Documents/SolveSpace/piston_groove.step"

# 1. Check native SLVS file
SLVS_EXISTS="false"
SLVS_CREATED_DURING_TASK="false"
SLVS_SIZE="0"

if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c %s "$SLVS_PATH" 2>/dev/null || echo "0")
    MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED_DURING_TASK="true"
    fi
    
    # Copy file to /tmp for verifier access
    cp "$SLVS_PATH" /tmp/agent_piston_groove.slvs
    chmod 666 /tmp/agent_piston_groove.slvs
else
    # Create empty file so copy_from_env doesn't fail completely
    touch /tmp/agent_piston_groove.slvs
    chmod 666 /tmp/agent_piston_groove.slvs
fi

# 2. Check exported STEP file
STEP_EXISTS="false"
STEP_CREATED_DURING_TASK="false"
STEP_SIZE="0"
STEP_HEADER=""

if [ -f "$STEP_PATH" ]; then
    STEP_EXISTS="true"
    STEP_SIZE=$(stat -c %s "$STEP_PATH" 2>/dev/null || echo "0")
    MTIME=$(stat -c %Y "$STEP_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        STEP_CREATED_DURING_TASK="true"
    fi
    # Extract first few lines to check for STEP ISO header
    STEP_HEADER=$(head -n 5 "$STEP_PATH" | tr '\n' ' ' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result (use temp file for permission safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_created_during_task": $SLVS_CREATED_DURING_TASK,
    "slvs_size_bytes": $SLVS_SIZE,
    "step_exists": $STEP_EXISTS,
    "step_created_during_task": $STEP_CREATED_DURING_TASK,
    "step_size_bytes": $STEP_SIZE,
    "step_header": "$STEP_HEADER",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="