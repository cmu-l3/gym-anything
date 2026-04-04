#!/system/bin/sh
echo "=== Exporting LED Resistor Calculator results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/tasks/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if agent created the screenshot as requested
AGENT_SCREENSHOT="/sdcard/tasks/led_resistor_result.png"
AGENT_SCREENSHOT_EXISTS="false"
AGENT_SCREENSHOT_SIZE="0"
AGENT_SCREENSHOT_VALID="false"

if [ -f "$AGENT_SCREENSHOT" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    AGENT_SCREENSHOT_SIZE=$(stat -c%s "$AGENT_SCREENSHOT" 2>/dev/null || echo "0")
    AGENT_SCREENSHOT_TIME=$(stat -c%Y "$AGENT_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Check if created AFTER task start (anti-gaming)
    if [ "$AGENT_SCREENSHOT_TIME" -gt "$TASK_START" ]; then
        AGENT_SCREENSHOT_VALID="true"
    fi
fi

# 2. Capture system verification screenshot (what is actually on screen now)
SYSTEM_SCREENSHOT="/sdcard/tasks/system_final_state.png"
screencap -p "$SYSTEM_SCREENSHOT"

# 3. Dump UI hierarchy to XML for content verification
UI_DUMP_PATH="/sdcard/tasks/led_resistor_ui_dump.xml"
uiautomator dump "$UI_DUMP_PATH" 2>/dev/null || echo "UI dump failed"

# 4. Check if app is in foreground
PACKAGE="com.hsn.electricalcalculations"
APP_IN_FOREGROUND="false"
if dumpsys window windows | grep -q "mCurrentFocus.*$PACKAGE"; then
    APP_IN_FOREGROUND="true"
fi

# 5. Create JSON result file
JSON_PATH="/sdcard/tasks/led_resistor_result.json"
cat > "$JSON_PATH" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "agent_screenshot_size": $AGENT_SCREENSHOT_SIZE,
    "agent_screenshot_valid_timestamp": $AGENT_SCREENSHOT_VALID,
    "app_in_foreground": $APP_IN_FOREGROUND,
    "ui_dump_path": "$UI_DUMP_PATH",
    "system_screenshot_path": "$SYSTEM_SCREENSHOT",
    "agent_screenshot_path": "$AGENT_SCREENSHOT"
}
EOF

# Set permissions ensuring host can read
chmod 666 "$JSON_PATH" "$UI_DUMP_PATH" "$SYSTEM_SCREENSHOT" "$AGENT_SCREENSHOT" 2>/dev/null || true

echo "Export complete. Result saved to $JSON_PATH"