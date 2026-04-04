#!/bin/bash
set -e

echo "=== Exporting share_youtube_video results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if Meeting is still active (Window Title)
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
MEETING_ACTIVE="false"
if echo "$WINDOW_TITLE" | grep -qi "fitness-demo-session\|Jitsi Meet"; then
    MEETING_ACTIVE="true"
fi

# 2. Capture Final Screenshot (clean view)
focus_firefox
DISPLAY=:1 xdotool mousemove 960 500  # Center screen
sleep 1
take_screenshot /tmp/task_final.png

# 3. DOM/Console Evidence Check
# We will use xdotool to run a JS check in console and capture the result visually
# This helps the VLM verification
echo "Running console checks..."
DISPLAY=:1 xdotool key F12
sleep 2
DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+k
sleep 1
# Clear console
DISPLAY=:1 xdotool key --clearmodifiers ctrl+l
sleep 0.5

# Type JS check to find YouTube iframe
JS_CHECK='document.querySelectorAll("iframe[src*=\"youtube\"], #sharedVideo, .shared-video").length > 0 ? "VIDEO_FOUND" : "VIDEO_NOT_FOUND"'
DISPLAY=:1 xdotool type --clearmodifiers --delay 10 "$JS_CHECK"
DISPLAY=:1 xdotool key Return
sleep 1

# Take screenshot of console output
take_screenshot /tmp/task_console_evidence.png

# Close dev tools
DISPLAY=:1 xdotool key F12
sleep 1

# 4. Detect "Do Nothing" via screenshot comparison
SCREENSHOT_CHANGED="false"
if [ -f /tmp/task_initial.png ] && [ -f /tmp/task_final.png ]; then
    # Compare images using ImageMagick (metric RMSE)
    DIFF=$(compare -metric RMSE /tmp/task_initial.png /tmp/task_final.png /dev/null 2>&1 | awk -F'[()]' '{print $2}' || echo "0")
    # If diff > 0.01, assume change
    IS_DIFF=$(echo "$DIFF > 0.01" | bc -l 2>/dev/null || echo "0")
    if [ "$IS_DIFF" -eq 1 ]; then
        SCREENSHOT_CHANGED="true"
    fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "meeting_active": $MEETING_ACTIVE,
    "window_title": "$WINDOW_TITLE",
    "screenshot_changed": $SCREENSHOT_CHANGED,
    "final_screenshot_path": "/tmp/task_final.png",
    "console_screenshot_path": "/tmp/task_console_evidence.png",
    "initial_screenshot_path": "/tmp/task_initial.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="