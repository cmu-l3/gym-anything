#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting ADF Unit Root Test Results ==="

# 1. Capture Final State Visuals
take_screenshot /tmp/task_final.png

# 2. Gather Task Artifacts
OUTPUT_FILE="/home/ga/Documents/gretl_output/adf_results.txt"
GROUND_TRUTH_FILE="/tmp/ground_truth_output.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Analyze Output File Metadata
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_CONTENT=""
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    # Check if file was created/modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (limit size to prevent massive JSONs)
    # We escape double quotes for JSON safety later or use python to generate json
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" | head -c 50000)
fi

# 4. Gather Ground Truth Content
GT_CONTENT=""
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GT_CONTENT=$(cat "$GROUND_TRUTH_FILE")
fi

# 5. Check Application State
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# 6. Generate Result JSON using Python for safe serialization
# (Avoids bash string escaping hell)
python3 -c "
import json
import os
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'output_size_bytes': $OUTPUT_SIZE,
    'app_was_running': $APP_RUNNING,
    'output_content': '''$OUTPUT_CONTENT''',
    'ground_truth_content': '''$GT_CONTENT''',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 7. Secure Result File
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="