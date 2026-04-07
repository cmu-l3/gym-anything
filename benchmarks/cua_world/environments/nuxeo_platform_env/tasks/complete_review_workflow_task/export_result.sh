#!/bin/bash
# export_result.sh for complete_review_workflow_task
# Queries Nuxeo API for workflow status and audit logs, exports to JSON.

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python script to query API and generate result JSON
# We do this inside the container because it has direct access to localhost:8080
# and avoids complex curl parsing in bash.

python3 -c "
import sys, json, requests, time, os

NUXEO_URL = 'http://localhost:8080/nuxeo'
AUTH = ('Administrator', 'Administrator')

def get_file_content(path, default=''):
    if os.path.exists(path):
        with open(path, 'r') as f:
            return f.read().strip()
    return default

# Load Setup Data
wf_id = get_file_content('/tmp/task_workflow_id.txt')
doc_uid = get_file_content('/tmp/task_doc_uid.txt')
try:
    start_time = int(get_file_content('/tmp/task_start_time.txt', '0'))
except:
    start_time = 0

result = {
    'workflow_id': wf_id,
    'doc_uid': doc_uid,
    'task_completed': False,
    'workflow_ended': False,
    'comment_found': False,
    'comment_text': '',
    'audit_events': [],
    'timestamp_check': True
}

if wf_id:
    # Check 1: Is the task still pending?
    try:
        resp = requests.get(f'{NUXEO_URL}/api/v1/task', params={'workflowInstanceId': wf_id, 'userId': 'Administrator'}, auth=AUTH)
        if resp.status_code == 200:
            tasks = resp.json().get('entries', [])
            result['pending_task_count'] = len(tasks)
            # If 0 tasks pending, agent likely completed it
            if len(tasks) == 0:
                result['task_completed'] = True
    except Exception as e:
        result['error_tasks'] = str(e)

    # Check 2: Is workflow ended?
    try:
        resp = requests.get(f'{NUXEO_URL}/api/v1/workflow/{wf_id}', auth=AUTH)
        if resp.status_code == 404:
            # Workflow cleaned up = ended
            result['workflow_ended'] = True
            result['workflow_state'] = 'cleaned_up'
        elif resp.status_code == 200:
            state = resp.json().get('state')
            result['workflow_state'] = state
            if state in ['ended', 'done', 'canceled']:
                result['workflow_ended'] = True
    except Exception as e:
        result['error_workflow'] = str(e)

# Check 3: Audit Log for Comment
if doc_uid:
    try:
        resp = requests.get(f'{NUXEO_URL}/api/v1/id/{doc_uid}/@audit', auth=AUTH)
        if resp.status_code == 200:
            entries = resp.json().get('entries', [])
            # Filter events after task start
            # eventDate is ISO8601, simplified check
            # We look for 'workflowTaskCompleted' or 'documentModified' with comment
            relevant_events = []
            for e in entries:
                # Basic check: is it a workflow event?
                cid = e.get('category', '')
                eid = e.get('eventId', '')
                comment = e.get('comment', '')
                
                if 'workflow' in cid.lower() or 'workflow' in eid.lower():
                    relevant_events.append(e)
                    if comment and 'Reviewed and approved' in comment:
                        result['comment_found'] = True
                        result['comment_text'] = comment
            
            result['audit_events_count'] = len(relevant_events)
    except Exception as e:
        result['error_audit'] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON generated.')
"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="