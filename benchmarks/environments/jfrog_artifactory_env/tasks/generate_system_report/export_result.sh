#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting generate_system_report task results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_FILE="/home/ga/system_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
    
    # Read content (base64 encode to safely transport via JSON)
    REPORT_CONTENT=$(base64 -w 0 "$REPORT_FILE")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Read Ground Truth (captured at setup)
GT_VERSION_JSON=$(cat /tmp/ground_truth_version.json 2>/dev/null || echo "{}")
GT_REPOS_JSON=$(cat /tmp/ground_truth_repos.json 2>/dev/null || echo "[]")
GT_STORAGE_JSON=$(cat /tmp/ground_truth_storage.json 2>/dev/null || echo "{}")

# 4. Create Result JSON
# Using python to safely construct JSON prevents bash escaping hell
python3 -c "
import json
import sys

try:
    result = {
        'task_start': $TASK_START,
        'report_exists': $REPORT_EXISTS,
        'report_file_path': '$REPORT_FILE',
        'file_created_during_task': $FILE_CREATED_DURING_TASK,
        'report_size_bytes': $REPORT_SIZE,
        'report_content_b64': '$REPORT_CONTENT',
        'ground_truth': {
            'version': json.loads('''$GT_VERSION_JSON'''),
            'repos': json.loads('''$GT_REPOS_JSON'''),
            'storage': json.loads('''$GT_STORAGE_JSON''')
        }
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="