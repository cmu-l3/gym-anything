#!/bin/bash
set -e
echo "=== Exporting configure_prejoin_state result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (Visual evidence of being in meeting + muted state)
take_screenshot /tmp/task_final.png

# 2. Extract Internal Jitsi State via Browser Console -> Window Title Hack
# This is necessary because we can't easily attach a debugger to the container's firefox from shell.
# We inject JS to put the state into the document title, then read the window title.

echo "Extracting Jitsi state..."
focus_firefox

# Open Web Console (Ctrl+Shift+K)
DISPLAY=:1 xdotool key --delay 100 ctrl+shift+k
sleep 2

# Type JS command to dump state to title
# We use a unique prefix "JITSI_RES:" to find it later
JS_CMD='try { document.title = "JITSI_RES:" + JSON.stringify({ audioMuted: APP.conference.isLocalAudioMuted(), videoMuted: APP.conference.isLocalVideoMuted(), displayName: APP.conference.getLocalDisplayName(), roomName: APP.conference.roomName }); } catch(e) { document.title = "JITSI_RES:ERROR"; }'

# Type the command (using xclip to paste is faster/safer than typing)
echo -n "$JS_CMD" | xclip -selection clipboard
DISPLAY=:1 xdotool key ctrl+v
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 2

# Read the window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname)
echo "Captured Window Title: $WINDOW_TITLE"

# Parse JSON from title if present
JSON_STATE="{}"
if [[ "$WINDOW_TITLE" == *"JITSI_RES:"* ]]; then
    # Extract everything after JITSI_RES:
    JSON_STATE=$(echo "$WINDOW_TITLE" | sed 's/.*JITSI_RES://')
else
    echo "WARNING: Could not extract state via title hack."
    JSON_STATE='{"error": "Extraction failed"}'
fi

# 3. Check if Application (Firefox) is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Construct Final JSON Result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Write to temp file first
cat > /tmp/task_result_temp.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "jitsi_state": $JSON_STATE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json