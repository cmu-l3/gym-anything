#!/system/bin/sh
echo "=== Exporting view_ifr_low_chart results ==="

# Define paths
DATA_DIR="/sdcard/com.ds.avare"
START_TIME_FILE="/sdcard/task_start_time.txt"
INITIAL_FILE_LIST="/sdcard/initial_files.txt"
FINAL_FILE_LIST="/sdcard/final_files.txt"
RESULT_JSON="/sdcard/task_result.json"

# Capture final screenshot (system level)
screencap -p /sdcard/task_final.png

# Record final file state
if [ -d "$DATA_DIR" ]; then
    ls -R "$DATA_DIR" > "$FINAL_FILE_LIST"
else
    echo "Data dir not found" > "$FINAL_FILE_LIST"
fi

# Calculate file changes
# Note: Android shell has limited diff capabilities, we'll do simple line counting
INITIAL_COUNT=$(wc -l < "$INITIAL_FILE_LIST")
FINAL_COUNT=$(wc -l < "$FINAL_FILE_LIST")
FILES_ADDED=$((FINAL_COUNT - INITIAL_COUNT))

# Check for specific "IFR" or "Low" keywords in the new file list difference
# This is a rough check; strict verification happens in python
NEW_FILES_CONTENT=$(grep -v -F -f "$INITIAL_FILE_LIST" "$FINAL_FILE_LIST" | grep -i "Low\|IFR")
if [ -n "$NEW_FILES_CONTENT" ]; then
    IFR_FILES_DETECTED="true"
else
    IFR_FILES_DETECTED="false"
fi

# Check if agent saved the specific screenshot
if [ -f "/sdcard/ifr_chart_result.png" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    AGENT_SCREENSHOT_SIZE=$(stat -c %s "/sdcard/ifr_chart_result.png")
else
    AGENT_SCREENSHOT_EXISTS="false"
    AGENT_SCREENSHOT_SIZE="0"
fi

# Check if app is running
if pidof com.ds.avare > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Create JSON result
echo "{" > "$RESULT_JSON"
echo "  \"files_added_count\": $FILES_ADDED," >> "$RESULT_JSON"
echo "  \"ifr_files_detected\": $IFR_FILES_DETECTED," >> "$RESULT_JSON"
echo "  \"agent_screenshot_exists\": $AGENT_SCREENSHOT_EXISTS," >> "$RESULT_JSON"
echo "  \"agent_screenshot_size\": $AGENT_SCREENSHOT_SIZE," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "=== Export complete ==="
cat "$RESULT_JSON"