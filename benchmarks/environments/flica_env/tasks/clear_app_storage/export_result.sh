#!/system/bin/sh
# Export script for clear_app_storage task
# Captures final state, checks app installation, and exports results

echo "=== Exporting task results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
PACKAGE="com.robert.fcView"

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png
echo "Final screenshot captured."

# 2. Dump Final UI Hierarchy
uiautomator dump /sdcard/final_state.xml 2>/dev/null
echo "Final UI dumped."

# 3. Check if app is still installed (Crucial: Agent shouldn't uninstall)
APP_INSTALLED="false"
if pm list packages | grep -q "$PACKAGE"; then
    APP_INSTALLED="true"
fi

# 4. Check if we are currently in the app (Flight Crew View)
# We use dumpsys window to see the focused package
CURRENT_FOCUS=$(dumpsys window | grep -E 'mCurrentFocus|mFocusedApp' | grep "$PACKAGE")
APP_FOCUSED="false"
if [ -n "$CURRENT_FOCUS" ]; then
    APP_FOCUSED="true"
fi

# 5. Create JSON Result
# We use a temp file pattern to ensure atomic write/permissions
TEMP_JSON="/sdcard/temp_result.json"
RESULT_JSON="/sdcard/task_result.json"

echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"app_installed\": $APP_INSTALLED," >> "$TEMP_JSON"
echo "  \"app_focused\": $APP_FOCUSED," >> "$TEMP_JSON"
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"," >> "$TEMP_JSON"
echo "  \"ui_dump_path\": \"/sdcard/final_state.xml\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

mv "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="