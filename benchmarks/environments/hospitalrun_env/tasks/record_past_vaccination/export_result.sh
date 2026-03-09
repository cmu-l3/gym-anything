#!/bin/bash
echo "=== Exporting record_past_vaccination results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from CouchDB
# We need to find the procedure record created by the agent.
# Criteria:
# - Type: procedure
# - Patient: Linked to Lucas Silva (patient_p1_vacc_001)
# - Created AFTER task start time

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_DOC_ID="patient_p1_vacc_001"

echo "Querying database for procedures linked to $PATIENT_DOC_ID..."

# We use python to filter the _all_docs response because simple grep is insufficient for JSON structure
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/all_docs.json

python3 -c "
import sys, json, time

try:
    with open('/tmp/all_docs.json') as f:
        data = json.load(f)
except:
    data = {'rows': []}

task_start = int($TASK_START_TIME)
# Buffer for clock skew
task_start_ms = (task_start - 10) * 1000 

found_records = []

for row in data.get('rows', []):
    doc = row.get('doc', {})
    # Unpack 'data' wrapper if present (HospitalRun convention)
    d = doc.get('data', doc)
    
    # Check type
    doc_type = d.get('type', doc.get('type', ''))
    if doc_type != 'procedure':
        continue
        
    # Check Patient Link
    # Patient field can be the ID string or a dict with 'id'
    pat = d.get('patient', {})
    pat_id = pat if isinstance(pat, str) else pat.get('id', '')
    
    # Also check friendly ID if stored
    if '$PATIENT_DOC_ID' not in pat_id and 'P_VACC_001' not in str(pat):
        continue
        
    # Get relevant fields
    proc_name = d.get('procedure', d.get('description', ''))
    notes = d.get('notes', '')
    
    # Get Date - typically stored as 'date', 'procedureDate', or 'visitDate'
    # Format might be ms timestamp (int) or ISO string
    proc_date = d.get('date', d.get('procedureDate', 0))
    
    # Get Metadata (Creation time)
    # HospitalRun often stores 'dateCreated' or 'metadata.createdDate'
    created_at = d.get('dateCreated', 0)
    # Fallback: check if doc ID has timestamp (common in some Pouch setups)
    
    # Identify if this is a candidate
    record = {
        'id': doc.get('_id'),
        'rev': doc.get('_rev'),
        'procedure_name': proc_name,
        'notes': notes,
        'procedure_date_raw': proc_date,
        'created_at': created_at,
        'full_doc': d
    }
    found_records.append(record)

result = {
    'records': found_records,
    'task_start_ts': task_start,
    'timestamp': time.time()
}

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Cleanup
rm -f /tmp/all_docs.json

# 3. Secure output
chmod 666 /tmp/task_result.json
echo "Exported $(jq '.records | length' /tmp/task_result.json) candidate records."
echo "=== Export complete ==="