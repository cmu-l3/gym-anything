#!/bin/bash
echo "=== Exporting report_database_stats result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/db_stats.txt"
TASK_START=$(cat /tmp/report_database_stats_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# CHECK OUTPUT FILE
# ------------------------------------------------------------------
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content safely (limit size)
    FILE_CONTENT=$(head -n 20 "$OUTPUT_FILE")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# ------------------------------------------------------------------
# CHECK APP STATUS
# ------------------------------------------------------------------
APP_RUNNING="false"
if pgrep -f "LobbyTrack" >/dev/null 2>&1 || pgrep -f "Lobby" >/dev/null 2>&1; then
    APP_RUNNING="true"
fi

# ------------------------------------------------------------------
# CREATE RESULT JSON
# ------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# We use python to safely dump the string content to JSON to avoid escaping issues
python3 -c "
import json
import os

content = \"\"\"$FILE_CONTENT\"\"\"

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_exists': $FILE_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'file_content': content,
    'app_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="