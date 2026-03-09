#!/bin/bash
echo "=== Exporting reschedule_visit results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get the Visit Document from CouchDB
# We fetch the specific ID we seeded.
echo "Fetching final visit state..."
VISIT_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_cameron_v1")

# 3. Get the initial revision (stored during setup)
INITIAL_REV=$(cat /tmp/initial_visit_rev.txt 2>/dev/null || echo "")

# 4. Create JSON result
# We parse the CouchDB document to extract key fields
python3 -c "
import sys, json
try:
    doc = json.loads('''$VISIT_DOC''')
    data = doc.get('data', doc) # Handle wrapped or unwrapped data
    
    result = {
        'doc_exists': '_id' in doc,
        'doc_id': doc.get('_id'),
        'current_rev': doc.get('_rev'),
        'initial_rev': '$INITIAL_REV',
        'start_date': data.get('startDate', ''),
        'end_date': data.get('endDate', ''),
        'reason': data.get('reasonForVisit', data.get('reason', '')),
        'status': data.get('status', ''),
        'patient': data.get('patient', '')
    }
except Exception as e:
    result = {'error': str(e), 'doc_exists': False}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json