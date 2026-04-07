#!/bin/bash
# Post-task script to gather verification data from within the container
echo "=== Exporting lock_and_comment results ==="

source /workspace/scripts/task_utils.sh

TASK_END_TIME=$(date +%s)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOC_PATH="/default-domain/workspaces/Templates/Contract-Template"
DOC_UID=$(cat /tmp/contract_template_uid.txt 2>/dev/null || echo "")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Final Document State (for Lock verification)
echo "Fetching document state..."
curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    -H "X-NXproperties: *" \
    "$NUXEO_URL/api/v1/path$DOC_PATH" > /tmp/doc_state.json

# 3. Get Final Comments (for Comment verification)
echo "Fetching comments..."
if [ -n "$DOC_UID" ]; then
    curl -s -u "$NUXEO_AUTH" \
        -H "Content-Type: application/json" \
        "$NUXEO_URL/api/v1/id/$DOC_UID/@comment" > /tmp/comments.json
else
    echo '{"entries": []}' > /tmp/comments.json
fi

# 4. Construct Result JSON
# We use Python to robustly combine these JSONs into one result file
python3 -c "
import json
import os
import time

try:
    # Load document state
    with open('/tmp/doc_state.json', 'r') as f:
        doc = json.load(f)
    
    # Load comments
    with open('/tmp/comments.json', 'r') as f:
        comments = json.load(f)
        
    result = {
        'task_start': $TASK_START_TIME,
        'task_end': $TASK_END_TIME,
        'doc_uid': '$DOC_UID',
        'lock_owner': doc.get('lockOwner', ''),
        'lock_created': doc.get('lockCreated', ''),
        'comments': comments.get('entries', []),
        'doc_found': 'uid' in doc,
        'screenshot_exists': os.path.exists('/tmp/task_final.png')
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
    print('Result JSON created successfully')
except Exception as e:
    print(f'Error creating result JSON: {e}')
    # Fallback minimal JSON
    with open('/tmp/task_result.json', 'w') as f:
        f.write('{\"error\": \"Failed to generate result\"}')
"

echo "=== Export complete ==="