#!/bin/bash
# export_result.sh - Post-task hook for spill_neutralization_agent_lookup
set -e

echo "=== Exporting Spill Neutralization Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Evidence
take_screenshot /tmp/task_final.png
echo "Final screenshot captured."

# 2. Collect Task Metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/neutralizer_inventory.csv"

# Check if application was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Verify file was modified/created AFTER task start (Anti-gaming)
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Create Result JSON
# We create a temporary JSON file to hold the metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "output_path": "$OUTPUT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions so verifier can read it
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export Complete ==="