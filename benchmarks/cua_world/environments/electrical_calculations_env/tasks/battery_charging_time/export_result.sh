#!/system/bin/sh
# Export results for battery_charging_time task

echo "=== Exporting Battery Charging Time results ==="

TASK_DIR="/sdcard/tasks/battery_charging_time"
RESULT_FILE="/sdcard/tasks/charge_time_result.txt"
SCREENSHOT_FILE="/sdcard/tasks/charge_time_screenshot.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_DIR/start_time.txt" 2>/dev/null || echo "0")

# Check result file
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME="0"
if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$RESULT_FILE" | head -n 1) # Read first line
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
fi

# Check screenshot file
SCREENSHOT_EXISTS="false"
SCREENSHOT_MTIME="0"
if [ -f "$SCREENSHOT_FILE" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_FILE" 2>/dev/null || echo "0")
else
    # Fallback: Capture current screen if agent didn't save one
    echo "Agent screenshot not found, capturing final state..."
    screencap -p "$SCREENSHOT_FILE" 2>/dev/null || true
    if [ -f "$SCREENSHOT_FILE" ]; then
        SCREENSHOT_EXISTS="true_fallback"
        SCREENSHOT_MTIME=$(date +%s)
    fi
fi

# Create JSON result
# Using a temp file construction method compatible with Android shell
JSON_PATH="$TASK_DIR/task_result.json"
echo "{" > "$JSON_PATH"
echo "  \"task_start\": $TASK_START," >> "$JSON_PATH"
echo "  \"task_end\": $TASK_END," >> "$JSON_PATH"
echo "  \"result_file_exists\": $FILE_EXISTS," >> "$JSON_PATH"
echo "  \"result_content\": \"$FILE_CONTENT\"," >> "$JSON_PATH"
echo "  \"result_file_mtime\": $FILE_MTIME," >> "$JSON_PATH"
echo "  \"screenshot_exists\": \"$SCREENSHOT_EXISTS\"," >> "$JSON_PATH"
echo "  \"screenshot_mtime\": $SCREENSHOT_MTIME," >> "$JSON_PATH"
echo "  \"screenshot_path\": \"$SCREENSHOT_FILE\"" >> "$JSON_PATH"
echo "}" >> "$JSON_PATH"

echo "Export complete. Result saved to $JSON_PATH"
cat "$JSON_PATH"