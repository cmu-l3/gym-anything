#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/gvsig_data/exports/africa_rivers_map.png"

# Gather file statistics
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    CREATED_DURING_TASK="false"
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "created_during_task": $CREATED_DURING_TASK,
    "app_running": $APP_RUNNING
}
EOF

# Safe move to /tmp/task_result.json
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="