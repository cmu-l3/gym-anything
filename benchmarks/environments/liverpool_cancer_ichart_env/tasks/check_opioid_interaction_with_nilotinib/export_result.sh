#!/system/bin/sh
# Export script for check_opioid_interaction_with_nilotinib
# Captures final UI state, screenshot, and logs for verification.

echo "=== Exporting Task Result ==="

PACKAGE="com.liverpooluni.ichartoncology"
OUTPUT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/final_screenshot.png"
UI_DUMP="/sdcard/ui_dump.xml"

# 1. Capture Final Screenshot
screencap -p "$FINAL_SCREENSHOT"
echo "Screenshot saved to $FINAL_SCREENSHOT"

# 2. Dump UI Hierarchy (for programmatic text verification)
# This allows checking if specific drug names are on screen without VLM
uiautomator dump "$UI_DUMP" 2>/dev/null
echo "UI hierarchy dumped to $UI_DUMP"

# 3. Check if App is in Foreground
# dumpsys window displays the current focused window
WINDOW_DUMP=$(dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp')
IS_APP_RUNNING="false"
if echo "$WINDOW_DUMP" | grep -q "$PACKAGE"; then
    IS_APP_RUNNING="true"
fi

# 4. Get Task Timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Create Result JSON
# We construct the JSON manually using echo since jq might not be on the device
echo "{" > "$OUTPUT_JSON"
echo "  \"task_start\": $TASK_START," >> "$OUTPUT_JSON"
echo "  \"task_end\": $TASK_END," >> "$OUTPUT_JSON"
echo "  \"app_package\": \"$PACKAGE\"," >> "$OUTPUT_JSON"
echo "  \"app_running_at_end\": $IS_APP_RUNNING," >> "$OUTPUT_JSON"
echo "  \"final_screenshot_path\": \"$FINAL_SCREENSHOT\"," >> "$OUTPUT_JSON"
echo "  \"ui_dump_path\": \"$UI_DUMP\"" >> "$OUTPUT_JSON"
echo "}" >> "$OUTPUT_JSON"

echo "Result JSON saved:"
cat "$OUTPUT_JSON"

echo "=== Export Complete ==="