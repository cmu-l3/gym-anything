#!/bin/bash
echo "=== Exporting Limiting Magnitude Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing anything
take_screenshot /tmp/task_final.png

# Paths
RESULTS_FILE="/home/ga/AstroImages/limiting_mag/limiting_mag_results.txt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME="0"
CREATED_DURING_TASK="false"

if [ -f "$RESULTS_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$RESULTS_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Read up to 5KB of the file
    FILE_CONTENT=$(head -c 5000 "$RESULTS_FILE")
fi

# Check if AstroImageJ is running
AIJ_RUNNING="false"
if is_aij_running; then
    AIJ_RUNNING="true"
fi

# Close AIJ cleanly if needed
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true

# Construct JSON Export
TEMP_JSON=$(mktemp /tmp/export.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json
import sys

content = """$FILE_CONTENT"""

result = {
    "file_exists": "$FILE_EXISTS" == "true",
    "created_during_task": "$CREATED_DURING_TASK" == "true",
    "file_mtime": int("$FILE_MTIME"),
    "aij_running_at_end": "$AIJ_RUNNING" == "true",
    "file_content": content
}

print(json.dumps(result, indent=2))
PYEOF

# Move securely
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "=== Export Complete ==="