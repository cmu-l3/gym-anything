#!/system/bin/sh
echo "=== Exporting set_map_2d_north_up results ==="

TASK_DIR="/sdcard/tasks/set_map_2d_north_up"
OUTPUT_JSON="$TASK_DIR/task_result.json"

# Get task start time
if [ -f "$TASK_DIR/task_start_time.txt" ]; then
    START_TIME=$(cat "$TASK_DIR/task_start_time.txt")
else
    START_TIME=0
fi

# Function to check file status
check_file() {
    FILE_PATH="$1"
    if [ -f "$FILE_PATH" ]; then
        # Get modification time (stat in Android/Toybox might differ, using ls -l or stat depending on availability)
        # Using a simple check: is it newer than start time?
        FILE_TIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
        
        if [ "$FILE_TIME" -gt "$START_TIME" ]; then
            echo "true"
        else
            echo "false" # Exists but old
        fi
    else
        echo "false"
    fi
}

SETTINGS_SCREENSHOT_VALID=$(check_file "$TASK_DIR/settings_confirmation.png")
MAP_SCREENSHOT_VALID=$(check_file "$TASK_DIR/final_map_view.png")

# Check if app is in foreground
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT_FOCUS" | grep -q "com.sygic.aura"; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Create JSON result
# Note: creating raw JSON string carefully
echo "{" > "$OUTPUT_JSON"
echo "  \"task_start\": $START_TIME," >> "$OUTPUT_JSON"
echo "  \"settings_screenshot_valid\": $SETTINGS_SCREENSHOT_VALID," >> "$OUTPUT_JSON"
echo "  \"map_screenshot_valid\": $MAP_SCREENSHOT_VALID," >> "$OUTPUT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$OUTPUT_JSON"
echo "  \"settings_path\": \"$TASK_DIR/settings_confirmation.png\"," >> "$OUTPUT_JSON"
echo "  \"map_path\": \"$TASK_DIR/final_map_view.png\"" >> "$OUTPUT_JSON"
echo "}" >> "$OUTPUT_JSON"

echo "Result saved to $OUTPUT_JSON"
cat "$OUTPUT_JSON"
echo "=== Export complete ==="