#!/bin/bash
set -euo pipefail

echo "=== Exporting Ranked Choice Voting Tabulation Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Close ONLYOFFICE gracefully if possible
if pgrep -f "onlyoffice" > /dev/null; then
    DISPLAY=:1 xdotool search --name "ONLYOFFICE" windowactivate --sync key --delay 200 ctrl+s 2>/dev/null || true
    sleep 2
    DISPLAY=:1 xdotool search --name "ONLYOFFICE" windowactivate --sync key --delay 200 ctrl+q 2>/dev/null || true
    sleep 2
    pkill -f onlyoffice 2>/dev/null || true
fi

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/rcv_tabulation_final.xlsx"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Write verification metadata to JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "file_exists": $FILE_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "file_size": $FILE_SIZE,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move securely
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Results exported successfully."
cat /tmp/task_result.json