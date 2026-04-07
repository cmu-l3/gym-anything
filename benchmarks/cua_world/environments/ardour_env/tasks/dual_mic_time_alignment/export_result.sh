#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Dual-Mic Time Alignment Result ==="

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
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Write to temp file then copy (handles permissions)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/dual_mic_result.json 2>/dev/null || sudo rm -f /tmp/dual_mic_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/dual_mic_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/dual_mic_result.json
chmod 666 /tmp/dual_mic_result.json 2>/dev/null || sudo chmod 666 /tmp/dual_mic_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/dual_mic_result.json"
echo "=== Export Complete ==="