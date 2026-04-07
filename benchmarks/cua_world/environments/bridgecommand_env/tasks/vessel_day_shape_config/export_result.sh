#!/bin/bash
echo "=== Exporting Vessel Day Shape Config Result ==="

MODEL_FILE="/opt/bridgecommand/Models/Ownship/Dredger/boat.ini"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot of the editor if open, or desktop
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# Check if file exists
FILE_EXISTS="false"
FILE_MODIFIED="false"
CONTENT=""

if [ -f "$MODEL_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$MODEL_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Read content (limit size for safety)
    CONTENT=$(cat "$MODEL_FILE" | head -n 200)
else
    echo "ERROR: boat.ini not found at $MODEL_FILE"
fi

# Create result JSON using Python for safe escaping
python3 -c "
import json
import os

content = \"\"\"$CONTENT\"\"\"

result = {
    'file_exists': $FILE_EXISTS,
    'file_modified': $FILE_MODIFIED,
    'content': content,
    'file_path': '$MODEL_FILE'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"