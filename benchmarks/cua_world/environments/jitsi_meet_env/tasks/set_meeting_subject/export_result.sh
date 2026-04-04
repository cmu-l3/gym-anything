#!/bin/bash
set -e
echo "=== Exporting set_meeting_subject task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Get current window titles
# Jitsi Meet updates the window title to "Subject | Room | Jitsi Meet"
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Current windows:"
echo "$CURRENT_WINDOWS"

# Check if Firefox is running
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
# We export the raw window titles so the python verifier can do flexible matching
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    --arg windows "$CURRENT_WINDOWS" \
    --arg ff_running "$FIREFOX_RUNNING" \
    '{
        task_start: $start,
        task_end: $end,
        window_titles: $windows,
        firefox_running: $ff_running,
        screenshot_path: "/tmp/task_final_state.png"
    }' > "$TEMP_JSON"

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="