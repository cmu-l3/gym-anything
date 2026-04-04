#!/bin/bash
set -e
echo "=== Exporting raise_hand_speaker_stats results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Capture Final State ---

# 1. Bring up toolbar (if auto-hidden) by moving mouse to center
DISPLAY=:1 xdotool mousemove 960 600
sleep 1

# 2. Take final screenshot
take_screenshot /tmp/task_final_state.png
echo "Final screenshot captured"

# --- Verify App State ---

# Check if Firefox is running
FIREFOX_RUNNING="false"
if pgrep -f "firefox" > /dev/null 2>&1; then
    FIREFOX_RUNNING="true"
fi

# Attempt to get current URL to verify we are in the correct room
# (Using xdotool to focus URL bar and copy it)
CURRENT_URL=""
if [ "$FIREFOX_RUNNING" = "true" ]; then
    focus_firefox
    sleep 0.5
    # Ctrl+L to focus address bar
    DISPLAY=:1 xdotool key --clearmodifiers ctrl+l
    sleep 0.5
    # Ctrl+C to copy
    DISPLAY=:1 xdotool key --clearmodifiers ctrl+c
    sleep 0.5
    # Read clipboard
    CURRENT_URL=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null || echo "")
    
    # Return focus to page (Escape)
    DISPLAY=:1 xdotool key Escape
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "firefox_running": $FIREFOX_RUNNING,
    "current_url": "$CURRENT_URL",
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="