#!/bin/bash
set -euo pipefail

echo "=== Exporting Mars Rover Traverse Briefing Result ==="

# Take Final Screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# Source utilities if available to nicely close apps
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
    if is_onlyoffice_running; then
        focus_onlyoffice_window || true
        save_document ga :1
        sleep 2
        close_onlyoffice ga :1
        sleep 2
    fi
fi

# Force kill if still running
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
sleep 1

# Extract file details
OUTPUT_PATH="/home/ga/Documents/Presentations/traverse_briefing.pptx"
START_TS=$(cat /tmp/mars_task_start_ts 2>/dev/null || echo "0")
END_TS=$(date +%s)

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo 0)
    
    if [ "$FILE_MTIME" -ge "$START_TS" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Write JSON result
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << JSONEOF
{
  "task_name": "mars_rover_traverse_briefing",
  "task_start": $START_TS,
  "task_end": $END_TS,
  "output_file_exists": $FILE_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "output_file_size": $FILE_SIZE
}
JSONEOF

# Move securely
mv "$TEMP_JSON" /tmp/mars_task_result.json
chmod 666 /tmp/mars_task_result.json

echo "=== Export Complete ==="