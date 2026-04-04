#!/bin/bash
echo "=== Exporting update_imaging_indication results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Fetch the target imaging document
# We know the ID we seeded: imaging_p1_gregory_req1
DOC_JSON=$(hr_couch_get "imaging_p1_gregory_req1")

# 3. Read the initial revision we stored
INITIAL_REV=$(cat /tmp/initial_imaging_rev.txt 2>/dev/null || echo "")

# 4. Construct Result JSON
# We use python to safely construct the JSON to avoid escaping hell
python3 -c "
import json
import sys

try:
    doc = json.loads('''$DOC_JSON''')
    data = doc.get('data', doc) # HospitalRun often wraps in 'data', sometimes flat
except Exception:
    doc = {}
    data = {}

result = {
    'doc_exists': '_id' in doc,
    'doc_id': doc.get('_id'),
    'current_rev': doc.get('_rev'),
    'initial_rev': '$INITIAL_REV',
    'notes': data.get('notes', ''),
    'imaging_type': data.get('imagingType', ''),
    'patient_id': data.get('patientId', data.get('patient', '')),
    'screenshot_path': '/tmp/task_final.png',
    'task_start': $TASK_START,
    'task_end': $TASK_END
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so the host can read it (via copy_from_env)
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="