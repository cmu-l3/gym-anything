#!/bin/bash
echo "=== Exporting search_case_by_phrase result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/found_case_id.txt"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FOUND_ID=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FOUND_ID=$(cat "$OUTPUT_FILE" | tr -d '[:space:]')
    
    # Check modification time
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Get Ground Truth
GROUND_TRUTH_ID=$(cat /tmp/ground_truth_id.txt 2>/dev/null || echo "")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "found_id": "$FOUND_ID",
    "ground_truth_id": "$GROUND_TRUTH_ID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json