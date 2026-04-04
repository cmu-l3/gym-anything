#!/bin/bash
echo "=== Exporting artifact_search_inventory result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Constants
REPORT_PATH="/home/ga/artifact_inventory_report.txt"
GROUND_TRUTH_FILE="/tmp/ground_truth_metadata.json"
TASK_START_FILE="/tmp/task_start_time.txt"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Timestamps
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Report File
REPORT_EXISTS=false
REPORT_CREATED_DURING_TASK=false
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK=true
    fi
    
    # Read content (limit size to prevent issues)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 10000)
fi

# 4. Load Ground Truth
GROUND_TRUTH="[]"
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GROUND_TRUTH=$(cat "$GROUND_TRUTH_FILE")
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use python to construct safe JSON to avoid escaping hell in bash
python3 -c "
import json
import os

try:
    report_content = '''$REPORT_CONTENT'''
    ground_truth = $GROUND_TRUTH
    
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'report_exists': $REPORT_EXISTS,
        'report_created_during_task': $REPORT_CREATED_DURING_TASK,
        'report_content': report_content,
        'ground_truth': ground_truth,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('$TEMP_JSON', 'w') as f:
        json.dump(result, f)
except Exception as e:
    print(f'Error creating JSON: {e}')
"

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"