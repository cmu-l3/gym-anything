#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ------------------------------------------------------------------
# Query current lock states from Nuxeo API
# ------------------------------------------------------------------
echo "Querying final document states..."

# Python script to fetch states and dump to JSON
python3 -c "
import requests
import json
import time

auth = ('Administrator', 'Administrator')
base_url = 'http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects'
docs = ['Annual-Report-2023', 'Project-Proposal', 'Q3-Status-Report']

results = {}

for doc_name in docs:
    try:
        r = requests.get(f'{base_url}/{doc_name}', auth=auth, headers={'X-NXproperties': '*'})
        if r.status_code == 200:
            data = r.json()
            # Nuxeo returns 'lockOwner' field at top level if locked, else it might be missing or null
            lock_owner = data.get('lockOwner')
            # Sometimes lock info is in contextParameters, but top level is standard
            results[doc_name] = {
                'exists': True,
                'locked': bool(lock_owner),
                'lockOwner': lock_owner
            }
        else:
            results[doc_name] = {'exists': False, 'error': r.status_code}
    except Exception as e:
        results[doc_name] = {'exists': False, 'error': str(e)}

output = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'documents': results,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)
"

# Set permissions so verifier can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="