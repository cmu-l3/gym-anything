#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Stereo Image & Gain Staging Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# If Ardour is running, trigger a save before killing it
# We do this to ensure data isn't lost if the agent forgot to save,
# but the verifier will check if the agent successfully did the work.
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Read baseline
INITIAL_TRACKS=$(cat /tmp/initial_track_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Current state
CURRENT_TRACKS="0"
SESSION_MTIME="0"
if [ -f "$SESSION_FILE" ]; then
    CURRENT_TRACKS=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    SESSION_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Create result JSON
cat > /tmp/stereo_image_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "initial_track_count": $INITIAL_TRACKS,
    "current_track_count": $CURRENT_TRACKS,
    "task_start_timestamp": $TASK_START,
    "session_mtime": $SESSION_MTIME,
    "export_timestamp": "$(date +%s)"
}
EOF

echo "Result saved to /tmp/stereo_image_result.json"
echo "=== Export Complete ==="