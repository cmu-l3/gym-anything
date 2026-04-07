#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Immersive Exhibit Stem Formatting Result ==="

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

# Current state
CURRENT_TRACKS="0"
if [ -f "$SESSION_FILE" ]; then
    CURRENT_TRACKS=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Count exported mix file
EXPORT_EXISTS="false"
EXPORT_SIZE="0"
FINAL_FILE="/home/ga/Audio/exhibit_final/exhibit_mix.wav"

if [ -f "$FINAL_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$FINAL_FILE" 2>/dev/null || echo "0")
else
    # Check if they exported to the session directory by mistake
    DEFAULT_EXPORT=$(find "/home/ga/Audio/sessions/MyProject/export" -name "*.wav" -type f 2>/dev/null | head -1)
    if [ -n "$DEFAULT_EXPORT" ]; then
        EXPORT_EXISTS="true_wrong_location"
        EXPORT_SIZE=$(stat -c %s "$DEFAULT_EXPORT" 2>/dev/null || echo "0")
    fi
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Create result JSON
cat > /tmp/exhibit_formatting_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "current_track_count": $CURRENT_TRACKS,
    "export_exists": "$EXPORT_EXISTS",
    "export_size": $EXPORT_SIZE,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/exhibit_formatting_result.json"
echo "=== Export Complete ==="