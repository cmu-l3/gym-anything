#!/bin/bash
echo "=== Exporting process_backlogged_lab_request results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Document IDs
TARGET_ID=$(cat /tmp/target_doc_id.txt 2>/dev/null || echo "lab_req_target_old")
DISTRACTOR_ID=$(cat /tmp/distractor_doc_id.txt 2>/dev/null || echo "lab_req_distractor_new")

# 3. Query CouchDB for current state of documents
# We use the python helper to safely extract fields since structure can be nested in 'data' or top-level
echo "Querying CouchDB for target: $TARGET_ID"
TARGET_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${TARGET_ID}")

echo "Querying CouchDB for distractor: $DISTRACTOR_ID"
DISTRACTOR_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${DISTRACTOR_ID}")

# 4. Parse Results using Python
# This handles the complexity of HospitalRun's data model (sometimes fields are in root, sometimes in .data)
python3 -c "
import sys, json

try:
    target = json.loads('''$TARGET_JSON''')
    distractor = json.loads('''$DISTRACTOR_JSON''')
except:
    target = {}
    distractor = {}

def get_field(doc, field):
    # Check top level
    val = doc.get(field)
    if val: return val
    # Check data dict
    return doc.get('data', {}).get(field, '')

res = {
    'target_exists': '_id' in target,
    'target_status': get_field(target, 'status'),
    'target_result': get_field(target, 'result'),
    'distractor_exists': '_id' in distractor,
    'distractor_status': get_field(distractor, 'status'),
    'distractor_result': get_field(distractor, 'result'),
    'timestamp': '$(date +%s)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(res, f)
"

# Set permissions so verifier can read it
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json