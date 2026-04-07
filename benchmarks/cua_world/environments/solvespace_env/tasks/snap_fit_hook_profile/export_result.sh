#!/bin/bash
echo "=== Exporting snap_fit_hook_profile results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check SLVS file
SLVS_PATH="/home/ga/Documents/SolveSpace/snap_fit_hook.slvs"
if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_CREATED="true"
    else
        SLVS_CREATED="false"
    fi
    SLVS_SIZE=$(stat -c %s "$SLVS_PATH" 2>/dev/null || echo "0")
else
    SLVS_EXISTS="false"
    SLVS_CREATED="false"
    SLVS_SIZE="0"
fi

# Check STL file
STL_PATH="/home/ga/Documents/SolveSpace/snap_fit_hook.stl"
if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_MTIME=$(stat -c %Y "$STL_PATH" 2>/dev/null || echo "0")
    if [ "$STL_MTIME" -gt "$TASK_START" ]; then
        STL_CREATED="true"
    else
        STL_CREATED="false"
    fi
    STL_SIZE=$(stat -c %s "$STL_PATH" 2>/dev/null || echo "0")
else
    STL_EXISTS="false"
    STL_CREATED="false"
    STL_SIZE="0"
fi

# Check if application was running
APP_RUNNING=$(is_solvespace_running && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_created": $SLVS_CREATED,
    "slvs_size_bytes": $SLVS_SIZE,
    "stl_exists": $STL_EXISTS,
    "stl_created": $STL_CREATED,
    "stl_size_bytes": $STL_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy slvs to tmp so verifier can easily grab it
if [ "$SLVS_EXISTS" = "true" ]; then
    cp "$SLVS_PATH" /tmp/snap_fit_hook.slvs
    chmod 666 /tmp/snap_fit_hook.slvs
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="