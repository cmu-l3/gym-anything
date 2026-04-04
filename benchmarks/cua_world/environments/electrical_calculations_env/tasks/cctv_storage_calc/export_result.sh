#!/system/bin/sh
# Export script for cctv_storage_calc
# Runs on Android device

echo "=== Exporting CCTV Storage Result ==="

RESULT_FILE="/sdcard/cctv_storage_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Get timestamps
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Check output file
FILE_EXISTS="false"
FILE_CREATED_DURING="false"
CONTENT=""

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    # Android `stat` might be limited, but we check if it exists
    # For simplicity in this env, existence + content check is primary
    
    # Read content
    CONTENT=$(cat "$RESULT_FILE")
    
    # Check modification time if possible (simple check: it didn't exist at start)
    FILE_CREATED_DURING="true" 
fi

# Check if App is in foreground
APP_VISIBLE="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.hsn.electricalcalculations"; then
    APP_VISIBLE="true"
fi

# Create JSON output
# Note: creating clean JSON in shell can be tricky, keeping it simple
echo "{" > "$JSON_OUTPUT"
echo "  \"task_start\": $TASK_START," >> "$JSON_OUTPUT"
echo "  \"task_end\": $CURRENT_TIME," >> "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_content\": \"$CONTENT\"," >> "$JSON_OUTPUT"
echo "  \"app_visible\": $APP_VISIBLE" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "Export complete. JSON saved to $JSON_OUTPUT"
cat "$JSON_OUTPUT"