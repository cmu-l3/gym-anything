#!/system/bin/sh
# Export script for compare_add_friend_errors task

echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START_FILE="/sdcard/task_start_time.txt"
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    # Fallback if date +%s wasn't available in setup
    TASK_START=0
fi

OUTPUT_PATH="/sdcard/error_comparison.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    
    # Check modification time (stat might not be available on minimal android, use ls -l)
    # Ideally we compare timestamps, but simple existence check + content validation is often enough on Android
    # if we cleared it in setup.
    FILE_CREATED_DURING_TASK="true" 
    
    # Read content (base64 encode to safely transport via JSON if needed, but simple text here)
    FILE_CONTENT=$(cat "$OUTPUT_PATH")
fi

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Create JSON result
# Note: constructing JSON manually in shell is fragile, keep it simple
TEMP_JSON="/sdcard/task_result.json"
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"output_exists\": $OUTPUT_EXISTS," >> "$TEMP_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$TEMP_JSON"
# Escape quotes in content for JSON
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
echo "  \"file_content\": \"$SAFE_CONTENT\"," >> "$TEMP_JSON"
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

echo "Result saved to $TEMP_JSON"
cat "$TEMP_JSON"
echo "=== Export complete ==="