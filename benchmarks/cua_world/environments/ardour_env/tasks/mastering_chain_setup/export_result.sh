#!/bin/bash
echo "=== Exporting Mastering Chain Setup Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Capture session timestamps before we kill Ardour
# We DO NOT force a save here, as saving is part of the agent's task description
SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

SESSION_END_MTIME="0"
if [ -f "$SESSION_FILE" ]; then
    SESSION_END_MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

SESSION_START_MTIME=$(cat /tmp/session_start_mtime.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Kill Ardour gracefully
kill_ardour

# Create export JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "session_start_mtime": $SESSION_START_MTIME,
    "session_end_mtime": $SESSION_END_MTIME,
    "task_start_time": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="