#!/system/bin/sh
# Export script for check_sedative_interaction_with_crizotinib
# Runs on Android device

echo "=== Exporting Task Results ==="

TASK_DIR="/sdcard/tasks"
OUTPUT_FILE="$TASK_DIR/crizotinib_midazolam_result.txt"
RESULT_JSON="$TASK_DIR/task_result.json"
START_TIME_FILE="$TASK_DIR/task_start_time.txt"
FINAL_SCREENSHOT="/sdcard/final_screenshot.png"

# Capture final screenshot for evidence
screencap -p "$FINAL_SCREENSHOT"

# Get Task Start Time
START_TIME=0
if [ -f "$START_TIME_FILE" ]; then
    START_TIME=$(cat "$START_TIME_FILE")
fi

# Check Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check if file was modified after task start
    if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if App is running
APP_RUNNING="false"
if ps -A | grep -q "com.liverpooluni.ichartoncology"; then
    APP_RUNNING="true"
fi

# Construct JSON manually (Android sh often lacks jq)
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $START_TIME," >> "$RESULT_JSON"
echo "  \"output_file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"file_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"final_screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result JSON:"
cat "$RESULT_JSON"