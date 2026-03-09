#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting elasticity_hypothesis_script results ==="

# 1. Capture final screenshot (evidence of script editor usage)
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# 2. Gather file system evidence
OUTPUT_FILE="/home/ga/Documents/gretl_output/elasticity_test_results.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if Gretl is still running
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# 4. Create JSON result
# We do NOT read the file content into JSON here to avoid escaping issues.
# The verifier will copy the actual text file to verify content.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "output_file_path": "$OUTPUT_FILE"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"