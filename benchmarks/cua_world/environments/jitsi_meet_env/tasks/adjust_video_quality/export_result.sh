#!/bin/bash
set -e
echo "=== Exporting adjust_video_quality results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Check if Firefox is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Check if initial and final screenshots exist
INITIAL_EXISTS=$([ -f /tmp/task_initial_state.png ] && echo "true" || echo "false")
FINAL_EXISTS=$([ -f /tmp/task_final_state.png ] && echo "true" || echo "false")

# Compare screenshots to detect "do nothing" (requires ImageMagick)
# Returns 0 if identical, 1 if different (or error)
SCREENSHOTS_DIFFER="false"
if [ "$INITIAL_EXISTS" = "true" ] && [ "$FINAL_EXISTS" = "true" ]; then
    if command -v compare >/dev/null; then
        # Compare metric AE (Absolute Error) - count of different pixels
        DIFF_PIXELS=$(DISPLAY=:1 compare -metric AE /tmp/task_initial_state.png /tmp/task_final_state.png /tmp/diff.png 2>&1 || echo "0")
        # If more than 100 pixels changed, consider them different
        if [ "$DIFF_PIXELS" -gt 100 ]; then
            SCREENSHOTS_DIFFER="true"
        fi
    else
        # Fallback: check file sizes
        SIZE1=$(stat -c%s /tmp/task_initial_state.png)
        SIZE2=$(stat -c%s /tmp/task_final_state.png)
        if [ "$SIZE1" != "$SIZE2" ]; then
            SCREENSHOTS_DIFFER="true"
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "initial_screenshot_exists": $INITIAL_EXISTS,
    "final_screenshot_exists": $FINAL_EXISTS,
    "screenshots_differ": $SCREENSHOTS_DIFFER,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="