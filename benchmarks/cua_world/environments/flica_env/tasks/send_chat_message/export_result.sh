#!/system/bin/sh
# Export script for send_chat_message task
# Runs on Android environment

echo "=== Exporting send_chat_message results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
DURATION=$((TASK_END - TASK_START))

# Capture final UI state
# We try twice to ensure we get a valid dump
rm -f /sdcard/final_ui_state.xml
uiautomator dump /sdcard/final_ui_state.xml 2>/dev/null
if [ ! -f /sdcard/final_ui_state.xml ]; then
    sleep 1
    uiautomator dump /sdcard/final_ui_state.xml 2>/dev/null
fi

# Take final screenshot
screencap -p /sdcard/task_final_state.png 2>/dev/null

# Check if Flight Crew View is running (in foreground)
# We grep for the package in the window dump or process list
APP_RUNNING="false"
if dumpsys window windows | grep -q "mCurrentFocus.*com.robert.fcView"; then
    APP_RUNNING="true"
fi

# Simple grep check for the message in the UI dump (pre-verification hint)
MESSAGE_DETECTED="false"
if [ -f /sdcard/final_ui_state.xml ]; then
    if grep -q "Arriving gate B7" /sdcard/final_ui_state.xml; then
        MESSAGE_DETECTED="true"
    fi
fi

# Create JSON result
# Note: We construct JSON manually in shell
RESULT_JSON="/sdcard/task_result.json"
echo "{" > $RESULT_JSON
echo "  \"task_start\": $TASK_START," >> $RESULT_JSON
echo "  \"task_end\": $TASK_END," >> $RESULT_JSON
echo "  \"duration_seconds\": $DURATION," >> $RESULT_JSON
echo "  \"app_running\": $APP_RUNNING," >> $RESULT_JSON
echo "  \"message_detected_in_dump\": $MESSAGE_DETECTED," >> $RESULT_JSON
echo "  \"ui_dump_path\": \"/sdcard/final_ui_state.xml\"," >> $RESULT_JSON
echo "  \"screenshot_path\": \"/sdcard/task_final_state.png\"" >> $RESULT_JSON
echo "}" >> $RESULT_JSON

# Set permissions so host can read them (if needed)
chmod 666 /sdcard/task_result.json 2>/dev/null
chmod 666 /sdcard/final_ui_state.xml 2>/dev/null
chmod 666 /sdcard/task_final_state.png 2>/dev/null

echo "=== Export complete ==="
cat $RESULT_JSON