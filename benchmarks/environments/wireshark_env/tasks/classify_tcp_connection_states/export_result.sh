#!/bin/bash
set -e

echo "=== Exporting classify_tcp_connection_states result ==="

source /workspace/scripts/task_utils.sh

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_FILE="/home/ga/Documents/captures/tcp_connection_state_report.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check report file status
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -n 20) 
fi

# Load ground truth
GROUND_TRUTH="{}"
if [ -f /tmp/ground_truth.json ]; then
    GROUND_TRUTH=$(cat /tmp/ground_truth.json)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use Python to construct valid JSON with proper escaping
python3 -c "
import json
import sys
import os

try:
    report_content = sys.argv[1]
    ground_truth = json.loads(sys.argv[2])
    
    result = {
        'report_exists': sys.argv[3] == 'true',
        'report_created_during_task': sys.argv[4] == 'true',
        'report_path': '$REPORT_FILE',
        'report_content': report_content,
        'ground_truth': ground_truth,
        'timestamp': '$(date -Iseconds)'
    }
    
    with open('$TEMP_JSON', 'w') as f:
        json.dump(result, f, indent=4)
        
except Exception as e:
    print(f'Error creating JSON: {e}')
    # Fallback minimal JSON
    with open('$TEMP_JSON', 'w') as f:
        json.dump({'error': str(e)}, f)

" "$REPORT_CONTENT" "$GROUND_TRUTH" "$REPORT_EXISTS" "$REPORT_CREATED_DURING_TASK"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="