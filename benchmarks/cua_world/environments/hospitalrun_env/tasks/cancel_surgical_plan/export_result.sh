#!/bin/bash
echo "=== Exporting cancel_surgical_plan result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query CouchDB for the specific operative plan
PLAN_ID="operativePlan_p1_00501_target_plan"
echo "Fetching plan document: $PLAN_ID"

# We fetch the raw doc. Using python to safely handle JSON parsing/exporting
DOC_CONTENT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PLAN_ID}")

# 3. Check application state
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Create result JSON
# We use Python to construct the JSON to avoid escaping issues with the doc content
python3 -c "
import json
import sys
import os
import time

try:
    doc_content = json.loads('''$DOC_CONTENT''')
except:
    doc_content = {}

# Check when the document was last modified if possible (CouchDB doesn't give mtime directly, 
# but we can infer change if _rev starts with '2-' assuming we started at '1-')
doc_rev = doc_content.get('_rev', '0-')
was_modified = not doc_rev.startswith('1-')

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'plan_doc': doc_content,
    'doc_exists': '_id' in doc_content,
    'was_modified': was_modified,
    'app_was_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 5. Permission safety
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="