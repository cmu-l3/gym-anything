#!/bin/bash
echo "=== Exporting recession_impact_dummy result ==="

source /workspace/scripts/task_utils.sh

# 1. Define paths
OUTPUT_PATH="/home/ga/Documents/gretl_output/recession_results.txt"
TASK_START_FILE="/tmp/task_start_time.txt"

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Check Output File Status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH")
    
    # Check timestamp against task start
    if [ -f "$TASK_START_FILE" ]; then
        TASK_START=$(cat "$TASK_START_FILE")
        FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
        if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    else
        # Fallback if start time missing (shouldn't happen)
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Create Result JSON
# Using a temp file to avoid permission issues before copying
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# 5. Move JSON to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json