#!/system/bin/sh
echo "=== Exporting screen_antibiotic_safety_methotrexate results ==="

# 1. Capture final state
screencap -p /sdcard/task_final.png

# 2. Get timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/sdcard/mtx_antibiotic_screen.txt"

# 3. Check output file details
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    # Get file modification time (stat in Android generic usually supports -c %Y)
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (base64 encode to safely transport via JSON if needed, but here we just cat raw for the simple verifier)
    FILE_CONTENT=$(cat "$OUTPUT_PATH")
fi

# 4. Check if app is running (foreground)
APP_RUNNING="false"
if dumpsys window | grep -q "com.liverpooluni.ichartoncology"; then
    APP_RUNNING="true"
fi

# 5. Create JSON result
# Note: Android shell usually has limited JSON tools, so we construct manually
JSON_PATH="/sdcard/task_result.json"

echo "{" > "$JSON_PATH"
echo "  \"task_start\": $TASK_START," >> "$JSON_PATH"
echo "  \"task_end\": $TASK_END," >> "$JSON_PATH"
echo "  \"output_exists\": $OUTPUT_EXISTS," >> "$JSON_PATH"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_PATH"
echo "  \"app_running_at_end\": $APP_RUNNING," >> "$JSON_PATH"
# Safe string inclusion for content
echo "  \"file_content\": \"$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | tr '\n' '|')\"" >> "$JSON_PATH"
echo "}" >> "$JSON_PATH"

echo "Result exported to $JSON_PATH"
cat "$JSON_PATH"
echo "=== Export complete ==="