#!/bin/bash
# Export script for start_document_workflow task
# Captures final state including active workflows and tasks for verification.

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
ga_x "scrot /tmp/task_final.png" 2>/dev/null || true

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOC_UID=$(cat /tmp/target_doc_uid.txt 2>/dev/null)
INITIAL_WF_COUNT=$(cat /tmp/initial_workflow_count.txt 2>/dev/null || echo "0")

echo "Checking workflows for Doc UID: $DOC_UID"

# 3. Query Active Workflows on the Document
WORKFLOWS_JSON=$(nuxeo_api GET "/id/$DOC_UID/@workflow")

# 4. Query Tasks assigned to 'jsmith'
# We filter tasks that are related to our specific document
TASKS_JSON=$(nuxeo_api GET "/task?userId=jsmith&workflowModelName=SerialDocumentReview")

# 5. Check if App is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Prepare JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use python to construct the comprehensive result JSON safely
python3 -c "
import json
import os
import sys

try:
    workflows_resp = json.loads('''$WORKFLOWS_JSON''')
    tasks_resp = json.loads('''$TASKS_JSON''')
    
    workflows = workflows_resp.get('entries', [])
    tasks = tasks_resp.get('entries', [])
    
    # Filter tasks specifically for our document
    doc_tasks = [t for t in tasks if t.get('targetDocumentIds', [{}])[0].get('id') == '$DOC_UID']
    
    result = {
        'task_start': $TASK_START,
        'initial_workflow_count': int('$INITIAL_WF_COUNT'),
        'final_workflow_count': len(workflows),
        'active_workflows': workflows,
        'jsmith_tasks': doc_tasks,
        'app_running': '$APP_RUNNING' == 'true',
        'doc_uid': '$DOC_UID'
    }
    
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="