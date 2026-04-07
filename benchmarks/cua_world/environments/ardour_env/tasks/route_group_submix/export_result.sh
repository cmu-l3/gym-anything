#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Route Group Submix Result ==="

# Take final screenshot before any window manipulation
take_screenshot /tmp/task_end_screenshot.png

# Attempt to save the session gracefully if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        # Focus the window and trigger Ctrl+S
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    # Force kill after saving so session file is fully flushed and unlocked
    kill_ardour
fi

sleep 2

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Read baseline info
INITIAL_TRACKS=$(cat /tmp/initial_track_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
SESSION_MODIFIED=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")

# Extract current track and group counts natively
CURRENT_TRACKS="0"
CURRENT_GROUPS="0"
if [ -f "$SESSION_FILE" ]; then
    CURRENT_TRACKS=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    CURRENT_GROUPS=$(grep -c '<RouteGroup ' "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/route_group_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "initial_track_count": $INITIAL_TRACKS,
    "current_track_count": $CURRENT_TRACKS,
    "current_group_count": $CURRENT_GROUPS,
    "task_start_timestamp": $TASK_START,
    "session_modified_timestamp": $SESSION_MODIFIED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location safely
rm -f /tmp/route_group_submix_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/route_group_submix_result.json
chmod 666 /tmp/route_group_submix_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/route_group_submix_result.json"
echo "=== Export Complete ==="