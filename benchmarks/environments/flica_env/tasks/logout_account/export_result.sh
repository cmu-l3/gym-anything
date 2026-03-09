#!/system/bin/sh
# Export script for logout_account@1
# captures final state, verifies app status, and generates result JSON

echo "=== Exporting logout_account results ==="

PKG="com.robert.fcView"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Check if App is still installed (Anti-gaming)
APP_INSTALLED="false"
if pm list packages | grep -q "$PKG"; then
    APP_INSTALLED="true"
fi

# 3. Check if App process is running (Anti-gaming/Crash check)
APP_RUNNING="false"
if pidof "$PKG" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Analyze UI State
# We dump the UI to XML and grep for key strings
uiautomator dump /sdcard/final_ui.xml > /dev/null 2>&1
sleep 1

LOGIN_INDICATORS_FOUND="false"
FRIENDS_INDICATORS_FOUND="false"

if [ -f /sdcard/final_ui.xml ]; then
    # Check for Login indicators
    if cat /sdcard/final_ui.xml | grep -qi "LOG IN\|Log In\|Create Account\|Welcome"; then
        LOGIN_INDICATORS_FOUND="true"
    fi
    # Check for specific email/password fields if text not found
    if cat /sdcard/final_ui.xml | grep -qi "resource-id.*email"; then
        LOGIN_INDICATORS_FOUND="true"
    fi
    
    # Check for Friends page indicators (should be absent)
    if cat /sdcard/final_ui.xml | grep -qi "Add New Friend"; then
        FRIENDS_INDICATORS_FOUND="true"
    fi
    
    # Get file size for debug
    XML_SIZE=$(ls -l /sdcard/final_ui.xml | awk '{print $4}')
else
    XML_SIZE="0"
fi

# 5. Get Timestamps
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# 6. Create JSON Result
# We construct JSON manually in shell
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $START_TIME," >> "$RESULT_JSON"
echo "  \"task_end\": $END_TIME," >> "$RESULT_JSON"
echo "  \"app_installed\": $APP_INSTALLED," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"login_indicators_found\": $LOGIN_INDICATORS_FOUND," >> "$RESULT_JSON"
echo "  \"friends_indicators_found\": $FRIENDS_INDICATORS_FOUND," >> "$RESULT_JSON"
echo "  \"ui_dump_size\": $XML_SIZE," >> "$RESULT_JSON"
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"

# 7. Set permissions to ensure host can read
chmod 666 "$RESULT_JSON" /sdcard/task_final.png /sdcard/final_ui.xml 2>/dev/null || true

echo "=== Export complete ==="