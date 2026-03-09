#!/system/bin/sh
echo "=== Exporting Three-Phase Voltage Conversion Result ==="

WRITABLE_DIR="/sdcard/tmp/three_phase"
EXPECTED_SCREENSHOT="/sdcard/tasks/three_phase_voltage_conversion_result.png"
FALLBACK_SCREENSHOT="/sdcard/tmp/three_phase/final_state_fallback.png"
RESULT_JSON="$WRITABLE_DIR/result.json"

# Capture timestamps
TASK_START=$(cat "$WRITABLE_DIR/task_start_time.txt" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if agent saved the screenshot
AGENT_SCREENSHOT_EXISTS="false"
AGENT_SCREENSHOT_SIZE="0"
if [ -f "$EXPECTED_SCREENSHOT" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    AGENT_SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    # Verify timestamp (simple check if it's newer than start)
    FILE_TIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_FRESH="true"
    else
        FILE_FRESH="false"
    fi
else
    FILE_FRESH="false"
fi

# Always take a fallback screenshot of the current state for verification
# This ensures we can verify even if the agent failed to save the file but did the calculation
screencap -p "$FALLBACK_SCREENSHOT"

# Check if app is in foreground
APP_FOCUSED=$(dumpsys window | grep mCurrentFocus | grep "com.hsn.electricalcalculations" && echo "true" || echo "false")

# Create JSON result
# Note: Using simple string concatenation for JSON creation in sh
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"agent_screenshot_exists\": $AGENT_SCREENSHOT_EXISTS," >> "$RESULT_JSON"
echo "  \"agent_screenshot_fresh\": $FILE_FRESH," >> "$RESULT_JSON"
echo "  \"app_focused\": $APP_FOCUSED," >> "$RESULT_JSON"
echo "  \"fallback_screenshot_path\": \"$FALLBACK_SCREENSHOT\"," >> "$RESULT_JSON"
echo "  \"agent_screenshot_path\": \"$EXPECTED_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="