#!/system/bin/sh
# Export script for inventory_cancer_drug_list task

echo "=== Exporting inventory_cancer_drug_list result ==="

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png 2>/dev/null || true

# 2. Get Task Start Time
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Check Output File Status
OUTPUT_FILE="/sdcard/ichart_drug_inventory.txt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""
FIRST_DRUG=""
LAST_DRUG=""
TOTAL_COUNT="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Parse fields using simple grep/sed (robust against casing)
    FIRST_DRUG=$(echo "$FILE_CONTENT" | grep -i "First drug" | head -1 | sed 's/.*: *//' | tr -d '\r')
    LAST_DRUG=$(echo "$FILE_CONTENT" | grep -i "Last drug" | head -1 | sed 's/.*: *//' | tr -d '\r')
    TOTAL_COUNT=$(echo "$FILE_CONTENT" | grep -i "Total count" | head -1 | sed 's/[^0-9]*//g')
fi

# 4. Check if App is currently running/focused
APP_FOCUSED="false"
DUMPSYS=$(dumpsys window windows 2>/dev/null)
if echo "$DUMPSYS" | grep -i "mCurrentFocus" | grep -i "com.liverpooluni.ichartoncology"; then
    APP_FOCUSED="true"
fi

# 5. Create JSON Result
# Using a temporary file pattern to avoid partial writes
TEMP_JSON="/sdcard/temp_result.json"
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_raw": "$(echo "$FILE_CONTENT" | tr '\n' ' ' | sed 's/"/\\"/g')",
    "parsed_first_drug": "$(echo "$FIRST_DRUG" | sed 's/"/\\"/g')",
    "parsed_last_drug": "$(echo "$LAST_DRUG" | sed 's/"/\\"/g')",
    "parsed_total_count": "${TOTAL_COUNT:-0}",
    "app_focused_at_end": $APP_FOCUSED,
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /sdcard/task_result.json
chmod 666 /sdcard/task_result.json

echo "Export complete. Result saved to /sdcard/task_result.json"
cat /sdcard/task_result.json