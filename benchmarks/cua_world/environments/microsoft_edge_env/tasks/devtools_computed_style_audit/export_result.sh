#!/bin/bash
# export_result.sh - Export script for DevTools Computed Style Audit

echo "=== Exporting Task Result ==="

# 1. Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check for Output File
OUTPUT_PATH="/home/ga/Desktop/style_audit.json"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
JSON_CONTENT="{}"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    # Check modification time
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content
    JSON_CONTENT=$(cat "$OUTPUT_PATH")
fi

# 3. Check for Server Activity (Did they visit the page?)
# We can check the python server logs for GET / requests
SERVER_LOG="/tmp/server.log"
PAGE_VISITED="false"
if grep -q "GET / HTTP" "$SERVER_LOG"; then
    PAGE_VISITED="true"
fi

# 4. Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
# Use python to construct safe JSON to avoid quoting issues
python3 -c "
import json
import os

try:
    content = json.loads('''$JSON_CONTENT''')
except:
    content = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'page_visited': $PAGE_VISITED,
    'extracted_data': content
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Cleanup Server
SERVER_PID=$(cat /tmp/server_pid.txt 2>/dev/null)
if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
fi

# Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."
cat /tmp/task_result.json