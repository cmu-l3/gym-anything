#!/system/bin/sh
# Export script for verify_large_text_readability

echo "=== Exporting Task Results ==="

# 1. Capture timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check System Font Scale
# This is the primary proof that the agent changed the settings
FINAL_FONT_SCALE=$(settings get system font_scale)

# 3. Check Evidence Files
EVIDENCE_SCREENSHOT="/sdcard/large_text_test.png"
REPORT_FILE="/sdcard/readability_result.txt"

# Screenshot check
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
if [ -f "$EVIDENCE_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    # Android `stat` might be limited, using ls -l for basic checks or date comparison if available
    # simplified check: if it exists now and we deleted it in setup, it's new.
    SCREENSHOT_CREATED_DURING_TASK="true"
    SCREENSHOT_SIZE=$(ls -l "$EVIDENCE_SCREENSHOT" | awk '{print $4}')
else
    SCREENSHOT_SIZE="0"
fi

# Report file check
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE")
fi

# 4. Check App State (Focus)
# We want to see if the user returned to the app
CURRENT_FOCUS=$(dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' | grep "com.robert.fcView")
if [ -n "$CURRENT_FOCUS" ]; then
    APP_FOCUSED="true"
else
    APP_FOCUSED="false"
fi

# 5. Capture Final State Screenshot for VLM verification
screencap -p /sdcard/task_final.png

# 6. Create JSON Result
# careful with JSON syntax in shell
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"final_font_scale\": \"$FINAL_FONT_SCALE\"," >> /sdcard/task_result.json
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> /sdcard/task_result.json
echo "  \"screenshot_created_during_task\": $SCREENSHOT_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"report_exists\": $REPORT_EXISTS," >> /sdcard/task_result.json
echo "  \"report_content\": \"$REPORT_CONTENT\"," >> /sdcard/task_result.json
echo "  \"app_focused_at_end\": $APP_FOCUSED," >> /sdcard/task_result.json
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export Complete ==="