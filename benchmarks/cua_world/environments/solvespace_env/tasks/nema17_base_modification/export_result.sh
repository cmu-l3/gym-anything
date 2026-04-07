#!/bin/bash
echo "=== Exporting nema17_base_modification task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SLVS_PATH="/home/ga/Documents/SolveSpace/nema17_base.slvs"
STL_PATH="/home/ga/Documents/SolveSpace/nema17_base.stl"

SLVS_EXISTS="false"
STL_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
SLVS_SIZE="0"
STL_SIZE="0"

# Inspect the expected SLVS file
if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c %s "$SLVS_PATH" 2>/dev/null || echo "0")
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    
    # Anti-gaming: Ensure it was written AFTER the task began
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy to /tmp to ensure verifier.py can retrieve it securely
    cp "$SLVS_PATH" /tmp/nema17_base.slvs
    chmod 644 /tmp/nema17_base.slvs
fi

# Inspect the expected STL export
if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c %s "$STL_PATH" 2>/dev/null || echo "0")
fi

# Check application state
APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Capture Final state
take_screenshot /tmp/task_final.png

# Create result JSON securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "stl_exists": $STL_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "slvs_size_bytes": $SLVS_SIZE,
    "stl_size_bytes": $STL_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard retrieval location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="