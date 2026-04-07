#!/bin/bash
set -euo pipefail

echo "=== Exporting GDD Formatting Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing ONLYOFFICE
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Try to save the document gracefully if the agent left it open
if pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null; then
    echo "ONLYOFFICE is running, attempting graceful save..."
    DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
    sleep 1
    # Send Ctrl+S to save
    su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
    sleep 2
    # Send Ctrl+Q to quit
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
fi

# Hard kill if it's still running
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
sleep 1

# Check for the expected output file
OUTPUT_PATH="/home/ga/Documents/TextDocuments/Eldoria_GDD.docx"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Write summary JSON for the verifier
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK
}
EOF

chmod 666 /tmp/task_result.json

echo "Result metadata exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="