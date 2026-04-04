#!/system/bin/sh
echo "=== Exporting configure_server_url task results ==="

PACKAGE="org.farmos.app"
RESULT_FILE="/sdcard/task_result.json"
UI_DUMP_FILE="/sdcard/ui_dump.xml"
SCREENSHOT_FILE="/sdcard/task_final_state.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if App is in Foreground
FOCUSED_ACTIVITY=$(dumpsys activity activities 2>/dev/null | grep "mResumedActivity" | head -1)
if echo "$FOCUSED_ACTIVITY" | grep -q "$PACKAGE"; then
    APP_IN_FOREGROUND="true"
else
    APP_IN_FOREGROUND="false"
fi

# 2. Capture Screenshot
screencap -p "$SCREENSHOT_FILE"

# 3. Dump UI Hierarchy
# Note: farmOS is a hybrid app, so uiautomator might see webview content depending on accessibility config
rm -f "$UI_DUMP_FILE" 2>/dev/null
uiautomator dump "$UI_DUMP_FILE" > /dev/null 2>&1
UI_DUMP_EXISTS="false"
if [ -f "$UI_DUMP_FILE" ]; then
    UI_DUMP_EXISTS="true"
fi

# 4. Check internal storage/preferences (if possible via run-as)
# This attempts to read shared preferences where URL might be stored locally before connection
# Note: This often fails on non-debuggable apps/production builds, but we try.
SHARED_PREFS_CONTENT=""
if [ -d "/data/data/$PACKAGE" ]; then
    # Try generic cat via run-as (might fail)
    SHARED_PREFS_CONTENT=$(run-as $PACKAGE cat /data/data/$PACKAGE/shared_prefs/*.xml 2>/dev/null || echo "")
fi

# 5. Create Result JSON
# We use a temp file strategy although strict tempfile command isn't always available on Android
echo "{" > "$RESULT_FILE"
echo "  \"task_start\": $TASK_START," >> "$RESULT_FILE"
echo "  \"task_end\": $TASK_END," >> "$RESULT_FILE"
echo "  \"app_in_foreground\": $APP_IN_FOREGROUND," >> "$RESULT_FILE"
echo "  \"ui_dump_exists\": $UI_DUMP_EXISTS," >> "$RESULT_FILE"
echo "  \"screenshot_path\": \"$SCREENSHOT_FILE\"," >> "$RESULT_FILE"
echo "  \"ui_dump_path\": \"$UI_DUMP_FILE\"" >> "$RESULT_FILE"
echo "}" >> "$RESULT_FILE"

echo "=== Export complete ==="
cat "$RESULT_FILE"