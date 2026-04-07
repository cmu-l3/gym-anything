#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Vocal Stutter Edit Result ==="

# Take final screenshot for evidence
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
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

EXPORT_FILE="/home/ga/Audio/export/stutter_intro.wav"
EXPORT_EXISTS="false"
EXPORT_SIZE=0

if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE" 2>/dev/null || echo "0")
fi

# Create result JSON
cat > /tmp/vocal_stutter_edit_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "export_exists": $EXPORT_EXISTS,
    "export_size": $EXPORT_SIZE,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure file is readable by the host process
chmod 666 /tmp/vocal_stutter_edit_result.json 2>/dev/null || sudo chmod 666 /tmp/vocal_stutter_edit_result.json 2>/dev/null || true

echo "Result saved to /tmp/vocal_stutter_edit_result.json"
echo "=== Export Complete ==="