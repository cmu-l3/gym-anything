#!/bin/bash
set -e

echo "=== Exporting task results ==="

# 1. Basic info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/captures/dns_latency_report.txt"
GROUND_TRUTH_PATH="/tmp/dns_ground_truth.json"

# 2. Check output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (limit size to avoid huge logs)
    OUTPUT_CONTENT=$(head -c 5000 "$OUTPUT_PATH")
fi

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Prepare JSON result
# We include the ground truth here so verifier doesn't need to recompute it,
# but we read it from the hidden temp file created in setup.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use Python to construct valid JSON including the file content
python3 -c "
import json
import os
import sys

def safe_read(path):
    if os.path.exists(path):
        with open(path, 'r') as f:
            return f.read()
    return ''

def safe_read_json(path):
    content = safe_read(path)
    if content:
        try:
            return json.loads(content)
        except:
            return {}
    return {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': str('$OUTPUT_EXISTS').lower() == 'true',
    'file_created_during_task': str('$FILE_CREATED_DURING_TASK').lower() == 'true',
    'output_path': '$OUTPUT_PATH',
    'output_content': sys.argv[1],
    'screenshot_path': '/tmp/task_final.png',
    'ground_truth': safe_read_json('$GROUND_TRUTH_PATH')
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
" "$OUTPUT_CONTENT"

# 5. Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"