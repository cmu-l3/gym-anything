#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Blood Bank Inventory Analysis Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing ONLYOFFICE
sudo -u ga DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    sudo -u ga DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Try to save gracefully via UI
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 3
    close_onlyoffice ga :1
    sleep 2
fi

# Force kill if still running
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi
sleep 1

# Check outputs
TARGET_PATH="/home/ga/Documents/Spreadsheets/blood_bank_inventory.xlsx"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$TARGET_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_PATH" 2>/dev/null || echo 0)
    FILE_MTIME=$(stat -c%Y "$TARGET_PATH" 2>/dev/null || echo 0)
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
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

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="