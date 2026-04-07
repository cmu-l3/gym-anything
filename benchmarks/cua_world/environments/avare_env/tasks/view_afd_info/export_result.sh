#!/system/bin/sh
# Export script for view_afd_info task
# Runs on Android device

echo "=== Exporting view_afd_info results ==="

TASK_DIR="/sdcard/tasks/view_afd_info"
RESULT_JSON="$TASK_DIR/result.json"
PACKAGE="com.ds.avare"

# 1. Check if App is currently in foreground
# dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp'
# specific check for Avare package
APP_RUNNING="false"
if dumpsys window | grep -i "mCurrentFocus" | grep -q "$PACKAGE"; then
    APP_RUNNING="true"
fi

# 2. Dump UI Hierarchy (XML)
# This can help verify if specific text views are present if VLM is ambiguous
uiautomator dump "$TASK_DIR/final_hierarchy.xml" 2>/dev/null
UI_DUMP_EXISTS="false"
if [ -f "$TASK_DIR/final_hierarchy.xml" ]; then
    UI_DUMP_EXISTS="true"
fi

# 3. Take Final Screenshot
screencap -p "$TASK_DIR/final_state.png"

# 4. Check for 'KSQL' or 'San Carlos' in the UI dump (text verification)
TEXT_FOUND="false"
if [ "$UI_DUMP_EXISTS" = "true" ]; then
    if grep -q "San Carlos" "$TASK_DIR/final_hierarchy.xml" || grep -q "KSQL" "$TASK_DIR/final_hierarchy.xml"; then
        TEXT_FOUND="true"
    fi
fi

# 5. Create JSON result
# Note: printf is safer than cat for JSON on minimal shells, but cat heredoc works on most Android shells
cat > "$RESULT_JSON" <<EOF
{
    "app_running": $APP_RUNNING,
    "ui_dump_exists": $UI_DUMP_EXISTS,
    "target_text_found_in_xml": $TEXT_FOUND,
    "screenshot_path": "$TASK_DIR/final_state.png",
    "timestamp": "$(date)"
}
EOF

# 6. Set permissions so host can pull it
chmod 666 "$RESULT_JSON"
chmod 666 "$TASK_DIR/final_state.png" 2>/dev/null

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="