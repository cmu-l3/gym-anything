#!/system/bin/sh
echo "=== Exporting cancel_sent_request result ==="

# 1. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check if App is Running
APP_RUNNING="false"
if ps -A | grep -q "com.robert.fcView"; then
    APP_RUNNING="true"
fi

# 3. Dump UI Hierarchy (Primary Evidence)
uiautomator dump /sdcard/final_ui.xml >/dev/null 2>&1
UI_DUMP_EXISTS="false"
if [ -f /sdcard/final_ui.xml ]; then
    UI_DUMP_EXISTS="true"
fi

# 4. Check for existence of the target email in the final dump (Programmatic Check)
EMAIL_STILL_PRESENT="false"
if [ "$UI_DUMP_EXISTS" = "true" ]; then
    if grep -q "ghost_pilot@example.com" /sdcard/final_ui.xml; then
        EMAIL_STILL_PRESENT="true"
    fi
    
    # Also check if we are on the relevant screen (Requests/Sent)
    # This helps distinguish "cancelled" from "navigated away"
    ON_REQUESTS_SCREEN="false"
    if grep -i -q "Request" /sdcard/final_ui.xml; then
        ON_REQUESTS_SCREEN="true"
    fi
fi

# 5. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 6. Create JSON Result
echo "{
    \"task_start\": $TASK_START,
    \"task_end\": $TASK_END,
    \"app_running\": $APP_RUNNING,
    \"ui_dump_exists\": $UI_DUMP_EXISTS,
    \"email_still_present\": $EMAIL_STILL_PRESENT,
    \"on_requests_screen\": $ON_REQUESTS_SCREEN,
    \"screenshot_path\": \"/sdcard/task_final.png\",
    \"ui_dump_path\": \"/sdcard/final_ui.xml\"
}" > /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"