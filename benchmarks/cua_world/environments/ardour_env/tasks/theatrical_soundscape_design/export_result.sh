#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Theatrical Soundscape Design Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
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
SESSION_MODIFIED="0"
if [ -f "$SESSION_FILE" ]; then
    CURRENT_TRACKS=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    SESSION_MODIFIED=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Create result JSON
cat > /tmp/theatrical_soundscape_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "initial_track_count": $INITIAL_TRACKS,
    "current_track_count": $CURRENT_TRACKS,
    "task_start_timestamp": $TASK_START,
    "session_modified_timestamp": $SESSION_MODIFIED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/theatrical_soundscape_result.json"
echo "=== Export Complete ==="