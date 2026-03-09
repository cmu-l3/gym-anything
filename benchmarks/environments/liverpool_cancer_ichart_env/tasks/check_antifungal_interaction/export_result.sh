#!/system/bin/sh
# Export script for check_antifungal_interaction task
echo "=== Exporting check_antifungal_interaction results ==="

PACKAGE="com.liverpooluni.ichartoncology"
TASK_DIR="/sdcard/tasks"
RESULT_JSON="/sdcard/tasks/task_result.json"

# 1. Capture final screenshot
screencap -p "$TASK_DIR/final_state.png" 2>/dev/null
echo "Final screenshot captured."

# 2. Check if App is currently in foreground (Focus)
# We grep for mCurrentFocus to see if our package is active
CURRENT_FOCUS=$(dumpsys window | grep -i "mCurrentFocus" 2>/dev/null)
IS_APP_FOCUSED="false"
if echo "$CURRENT_FOCUS" | grep -qi "$PACKAGE"; then
    IS_APP_FOCUSED="true"
fi

# 3. Check if App is in Recents (was launched at least once)
# This helps distinguish "tried but minimized" from "never touched"
RECENT_TASKS=$(dumpsys activity recents 2>/dev/null | grep -i "$PACKAGE")
WAS_APP_LAUNCHED="false"
if [ -n "$RECENT_TASKS" ] || [ "$IS_APP_FOCUSED" = "true" ]; then
    WAS_APP_LAUNCHED="true"
fi

# 4. Get timestamps
START_TIME=$(cat "$TASK_DIR/task_start_time.txt" 2>/dev/null || echo "0")
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 5. Dump UI Hierarchy (XML)
# This provides text-based evidence of what is on screen (Drug names, etc.)
uiautomator dump "$TASK_DIR/final_ui.xml" 2>/dev/null
UI_DUMP_EXISTS="false"
if [ -f "$TASK_DIR/final_ui.xml" ]; then
    UI_DUMP_EXISTS="true"
    # Create a simplified text version of visible text for the verifier
    # (Simple grep to extract 'text="..."' attributes)
    grep -o 'text="[^"]*"' "$TASK_DIR/final_ui.xml" | cut -d'"' -f2 > "$TASK_DIR/visible_text.txt"
fi

# 6. Create JSON result
# We construct the JSON manually using echo/cat
cat > "$RESULT_JSON" << EOF
{
    "timestamp": "$(date)",
    "task_duration_seconds": $DURATION,
    "app_focused": $IS_APP_FOCUSED,
    "app_launched": $WAS_APP_LAUNCHED,
    "ui_dump_exists": $UI_DUMP_EXISTS,
    "screenshot_path": "$TASK_DIR/final_state.png"
}
EOF

# Set permissions so the host can read it
chmod 666 "$RESULT_JSON" 2>/dev/null
chmod 666 "$TASK_DIR/final_state.png" 2>/dev/null
chmod 666 "$TASK_DIR/visible_text.txt" 2>/dev/null

echo "Export complete. Result saved to $RESULT_JSON"