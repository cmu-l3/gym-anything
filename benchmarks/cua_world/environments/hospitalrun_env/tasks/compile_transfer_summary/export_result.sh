#!/bin/bash
echo "=== Exporting task results ==="

# 1. Record basic task info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check the output file
OUTPUT_PATH="/home/ga/transfer_summary.txt"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_MTIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    # Capture modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    # Read content (safely, first 2kb)
    OUTPUT_CONTENT=$(head -c 2048 "$OUTPUT_PATH")
fi

# 3. Take final screenshot for VLM verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Construct JSON result
# Using python to safely escape the content string for JSON
python3 -c "
import json
import os
import sys

content = '''$OUTPUT_CONTENT'''
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS,
    'file_mtime': $FILE_MTIME,
    'output_content': content,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# 5. Set permissions so the host can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="