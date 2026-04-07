#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
OUTPUT_FILE="/home/ga/OpenToonz/outputs/xsheet_report.html"
TASK_START_FILE="/tmp/task_start_time.txt"
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Initialize variables
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
CONTAINS_TARGET_STRING="false"
IS_VALID_HTML="false"
FILE_SIZE="0"

# Check file existence
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")

    # Check timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check for target string "HERO_WALK_V1"
    if grep -q "HERO_WALK_V1" "$OUTPUT_FILE"; then
        CONTAINS_TARGET_STRING="true"
    fi

    # Check for HTML structure (simple check for tags)
    if grep -qi "<html" "$OUTPUT_FILE" || grep -qi "<table" "$OUTPUT_FILE"; then
        IS_VALID_HTML="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "contains_target_string": $CONTAINS_TARGET_STRING,
    "is_valid_html": $IS_VALID_HTML,
    "file_size_bytes": $FILE_SIZE,
    "output_path": "$OUTPUT_FILE"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="