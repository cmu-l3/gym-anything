#!/bin/bash
set -e
echo "=== Exporting create_lab_request results ==="

source /workspace/scripts/task_utils.sh

# 1. Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_LAB_COUNT=$(cat /tmp/initial_lab_count.txt 2>/dev/null || echo "0")

# 3. Query CouchDB for ALL Lab requests
# We pull all docs and filter in Python to ensure we catch the new one
echo "Querying CouchDB for lab requests..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/all_docs.json

# 4. Process the data to find relevant lab requests
# We look for:
# - Type: lab
# - Created/Modified after TASK_START (using requestedDate or generic logic)
# - Linked to Kwame Mensah
python3 -c "
import sys, json, time

task_start = $TASK_START
initial_count = int('$INITIAL_LAB_COUNT')

try:
    with open('/tmp/all_docs.json') as f:
        data = json.load(f)
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(1)

found_labs = []
valid_labs_count = 0

rows = data.get('rows', [])
for row in rows:
    doc = row.get('doc', {})
    d = doc.get('data', doc) # HospitalRun often wraps data
    
    # Check type
    doc_type = doc.get('type') or d.get('type')
    if doc_type != 'lab':
        continue
        
    # Check patient linkage
    patient_ref = str(d.get('patient', ''))
    
    # Check for P00001, Kwame, or Mensah
    is_target_patient = ('P00001' in patient_ref or 
                         'Kwame' in patient_ref or 
                         'Mensah' in patient_ref or 
                         'patient_p1_1' in patient_ref)
                         
    if is_target_patient:
        valid_labs_count += 1
        
        # Check if created/modified recently
        # HospitalRun uses 'requestedDate' usually
        req_date = d.get('requestedDate')
        is_recent = False
        
        # Method A: Check timestamp if available
        if req_date:
            # format usually: 2026-03-07T06:25:00.000Z
            # simplistic check: if it parses and is > task_start
            try:
                # Basic string comparison for ISO dates often works if timezone consistent
                # but let's rely on the fact that pre-existing ones were counted in setup
                pass 
            except:
                pass
        
        # Method B: We rely on the COUNT increasing. 
        # But we also want to return the CONTENT of the new doc for verification.
        # We will return ALL labs for this patient, and the verifier 
        # will check if valid_labs_count > initial_count AND if the content matches.
        
        found_labs.append({
            'id': doc.get('_id'),
            'labType': d.get('labType'),
            'status': d.get('status'),
            'notes': d.get('notes') or d.get('description'), # field name varies by version
            'patient': patient_ref,
            'requestedDate': req_date,
            'raw_data': d
        })

result = {
    'task_start': task_start,
    'initial_count': initial_count,
    'final_count': valid_labs_count,
    'new_labs_created': (valid_labs_count > initial_count),
    'labs': found_labs,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 5. Clean up
rm -f /tmp/all_docs.json

echo "Export complete. Result:"
cat /tmp/task_result.json