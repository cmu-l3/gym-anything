#!/bin/bash
echo "=== Exporting VoIP Analysis Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/voip_report.txt"
GT_FILE="/tmp/voip_ground_truth.json"

# 3. Check report file status
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read content, limiting size to avoid issues
    REPORT_CONTENT=$(head -n 50 "$REPORT_PATH")
fi

# 4. Check if created during task
CREATED_DURING_TASK="false"
if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# 5. Read ground truth
GROUND_TRUTH="{}"
if [ -f "$GT_FILE" ]; then
    GROUND_TRUTH=$(cat "$GT_FILE")
fi

# 6. Create result JSON
# Use Python to safely construct JSON with proper escaping
python3 -c "
import json
import os
import sys

try:
    report_content = sys.argv[1]
    ground_truth = json.loads(sys.argv[2])
    
    result = {
        'report_exists': '$REPORT_EXISTS' == 'true',
        'created_during_task': '$CREATED_DURING_TASK' == 'true',
        'report_content': report_content,
        'ground_truth': ground_truth,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=4)
        
except Exception as e:
    print(f'Error creating result JSON: {e}')
    # Fallback minimal JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
" "$REPORT_CONTENT" "$GROUND_TRUTH"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="