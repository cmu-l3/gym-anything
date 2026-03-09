#!/bin/bash
set -e
echo "=== Exporting RTP Audio Extraction Results ==="

# Source task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Expected output
OUTPUT_FILE="/home/ga/Documents/captures/recovered_call.au"

# 1. Check File Existence
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    
    # 2. Check File Stats
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # 3. Check File Type (Magic Number/MIME)
    FILE_TYPE_RAW=$(file -b "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
    
    # 4. Anti-gaming: Check if created during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
    FILE_TYPE_RAW="none"
    CREATED_DURING_TASK="false"
fi

# 5. Check if Wireshark is still running
if pgrep -f "wireshark" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 6. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 7. Generate Result JSON
# Use python to safely generate JSON (avoids string escaping issues)
cat <<EOF > /tmp/gen_json.py
import json
import sys

data = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_type_output": "$FILE_TYPE_RAW",
    "created_during_task": $CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/temp_result.json', 'w') as f:
    json.dump(data, f, indent=2)
EOF

python3 /tmp/gen_json.py

# Move to final location safely
mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="