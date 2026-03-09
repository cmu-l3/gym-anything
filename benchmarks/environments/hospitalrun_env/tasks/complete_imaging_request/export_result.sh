#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting complete_imaging_request results ==="

# ─── 1. Capture Final State ─────────────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ─── 2. Fetch Document State from CouchDB ───────────────────────────────────
COUCH_BASE="http://couchadmin:test@localhost:5984"
DOC_ID="imaging_p1_0000001"

# Get the full document
DOC_JSON=$(curl -s "${COUCH_BASE}/main/${DOC_ID}")

# Get Initial Revision
INITIAL_REV=$(cat /tmp/initial_imaging_rev.txt 2>/dev/null || echo "")

# ─── 3. Construct Result JSON ───────────────────────────────────────────────
# We use Python to robustly parse the JSON and create the export object
python3 -c "
import json
import sys
import os
import time

try:
    doc = json.loads('''$DOC_JSON''')
    data = doc.get('data', {})
    
    initial_rev = '$INITIAL_REV'
    current_rev = doc.get('_rev', '')
    
    # Determine if modified
    modified = (initial_rev != '' and current_rev != '' and initial_rev != current_rev)
    
    result = {
        'doc_found': True,
        'status': data.get('status', ''),
        'result_text': data.get('result', ''),
        'patient_ref': data.get('patient', ''),
        'imaging_type_ref': data.get('imagingType', ''),
        'doc_rev': current_rev,
        'initial_rev': initial_rev,
        'is_modified': modified,
        'timestamp': time.time()
    }
except Exception as e:
    result = {
        'doc_found': False,
        'error': str(e)
    }

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so the host can read it via copy_from_env
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="