#!/bin/bash
echo "=== Exporting MHK Wave Energy results ==="

RESULT_FILE="/home/ga/Documents/SAM_Projects/wave_energy_results.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end_state.png 2>/dev/null || true

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
VALID_JSON="false"
DATA="{}"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check if valid JSON
    if jq empty "$RESULT_FILE" 2>/dev/null; then
        VALID_JSON="true"
        # Read the file data into a variable
        DATA=$(cat "$RESULT_FILE")
    fi
fi

# Create result JSON
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_created_during_task "$FILE_CREATED_DURING_TASK" \
    --arg file_size "$FILE_SIZE" \
    --argjson valid_json "$VALID_JSON" \
    --argjson data "$DATA" \
    '{
        file_exists: $file_exists,
        file_created_during_task: $file_created_during_task,
        file_size: $file_size,
        valid_json: $valid_json,
        data: $data
    }' > "$OUTPUT"

chmod 666 "$OUTPUT"

echo "Result exported to $OUTPUT"
cat "$OUTPUT"
echo "=== Export complete ==="