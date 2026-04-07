#!/bin/bash
echo "=== Exporting setup_iec62304_project results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check output file
OUTPUT_PATH="/home/ga/Documents/arch_test_coverage.json"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
OUTPUT_CONTENT=""
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi
    # Read content (truncate if too large)
    OUTPUT_CONTENT=$(head -c 10000 "$OUTPUT_PATH" 2>/dev/null | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
fi

# Check if app is running
APP_RUNNING="false"
if pgrep -f "reqview" > /dev/null; then
    APP_RUNNING="true"
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Export result JSON
cat > /tmp/task_result.json << RESULTEOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "created_during_task": $CREATED_DURING_TASK,
    "output_content": $OUTPUT_CONTENT,
    "app_running": $APP_RUNNING
}
RESULTEOF

chmod 644 /tmp/task_result.json 2>/dev/null || true
chmod 644 "$OUTPUT_PATH" 2>/dev/null || true

echo "=== Export complete ==="
