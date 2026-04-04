#!/system/bin/sh
echo "=== Exporting op_amp_noninverting_gain results ==="

TASK_START=$(cat /sdcard/tasks/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

RESULTS_FILE="/sdcard/tasks/op_amp_results.txt"
SCREENSHOT_FILE="/sdcard/tasks/op_amp_result.png"

# Check Results File
RESULTS_EXISTS="false"
RESULTS_CREATED_DURING_TASK="false"
RESULTS_CONTENT=""
if [ -f "$RESULTS_FILE" ]; then
    RESULTS_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$RESULTS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        RESULTS_CREATED_DURING_TASK="true"
    fi
    # Read content for export (limited size)
    RESULTS_CONTENT=$(cat "$RESULTS_FILE" | head -n 10)
fi

# Check Screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
if [ -f "$SCREENSHOT_FILE" ]; then
    SCREENSHOT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$SCREENSHOT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# Check if App is currently in foreground
APP_RUNNING="false"
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT_FOCUS" | grep -q "com.hsn.electricalcalculations"; then
    APP_RUNNING="true"
fi

# Create JSON export
EXPORT_JSON="/sdcard/tasks/task_export.json"
echo "{" > "$EXPORT_JSON"
echo "  \"task_start\": $TASK_START," >> "$EXPORT_JSON"
echo "  \"task_end\": $TASK_END," >> "$EXPORT_JSON"
echo "  \"results_file_exists\": $RESULTS_EXISTS," >> "$EXPORT_JSON"
echo "  \"results_created_during_task\": $RESULTS_CREATED_DURING_TASK," >> "$EXPORT_JSON"
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> "$EXPORT_JSON"
echo "  \"screenshot_created_during_task\": $SCREENSHOT_CREATED_DURING_TASK," >> "$EXPORT_JSON"
echo "  \"app_running_at_end\": $APP_RUNNING" >> "$EXPORT_JSON"
echo "}" >> "$EXPORT_JSON"

echo "Export generated at $EXPORT_JSON"