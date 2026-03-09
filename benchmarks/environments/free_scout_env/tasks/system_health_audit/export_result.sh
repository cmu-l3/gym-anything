#!/bin/bash
echo "=== Exporting System Health Audit Result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/system_audit.json"
GROUND_TRUTH_FILE="/var/lib/freescout/ground_truth/system_info.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output file status
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT="{}"
VALID_JSON="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content
    if jq . "$OUTPUT_FILE" >/dev/null 2>&1; then
        VALID_JSON="true"
        FILE_CONTENT=$(cat "$OUTPUT_FILE")
    else
        # If invalid JSON, try to read raw content safely
        RAW_CONTENT=$(cat "$OUTPUT_FILE" | head -c 1000 | sed 's/"/\\"/g')
        FILE_CONTENT="{\"raw_content\": \"$RAW_CONTENT\", \"error\": \"Invalid JSON\"}"
    fi
fi

# Read Ground Truth
GT_CONTENT="{}"
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GT_CONTENT=$(cat "$GROUND_TRUTH_FILE")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "valid_json": $VALID_JSON,
    "agent_output": $FILE_CONTENT,
    "ground_truth": $GT_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="