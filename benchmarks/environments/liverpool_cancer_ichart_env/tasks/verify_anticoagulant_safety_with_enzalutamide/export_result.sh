#!/system/bin/sh
echo "=== Exporting task results ==="

TASK_DIR="/sdcard/tasks/verify_anticoagulant_safety_with_enzalutamide"
RESULT_JSON="/sdcard/task_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_DIR/task_start_time.txt" 2>/dev/null || echo "0")

# Capture final screenshot
screencap -p "$TASK_DIR/final_state.png"

# Check if app is in foreground
PACKAGE="com.liverpooluni.ichartoncology"
APP_VISIBLE="false"
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    APP_VISIBLE="true"
fi

# Dump UI hierarchy (XML) - useful context for VLM if needed, or simple grep checks
uiautomator dump "$TASK_DIR/final_hierarchy.xml" 2>/dev/null || true

# Simple grep check on hierarchy for keywords (fallback signal)
HIERARCHY_CONTENT=""
if [ -f "$TASK_DIR/final_hierarchy.xml" ]; then
    HIERARCHY_CONTENT=$(cat "$TASK_DIR/final_hierarchy.xml")
fi

KEYWORDS_PRESENT="false"
if echo "$HIERARCHY_CONTENT" | grep -iq "Enzalutamide" && echo "$HIERARCHY_CONTENT" | grep -iq "Warfarin"; then
    KEYWORDS_PRESENT="true"
fi

# Create JSON result
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_visible": $APP_VISIBLE,
    "xml_keywords_present": $KEYWORDS_PRESENT,
    "final_screenshot_path": "$TASK_DIR/final_state.png",
    "initial_screenshot_path": "$TASK_DIR/initial_state.png"
}
EOF

# Set permissions so host can read
chmod 666 "$RESULT_JSON"
chmod 666 "$TASK_DIR/final_state.png" 2>/dev/null || true
chmod 666 "$TASK_DIR/initial_state.png" 2>/dev/null || true

echo "Result exported to $RESULT_JSON"