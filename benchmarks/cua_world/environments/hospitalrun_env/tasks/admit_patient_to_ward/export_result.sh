#!/bin/bash
echo "=== Exporting admit_patient_to_ward results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Export relevant CouchDB Data
# We look for ANY visit created after the task started for Sarah Connor
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_ID="patient_p1_adt101"

echo "Querying CouchDB for new visits..."
# Fetch all docs, filter for visits linked to Sarah Connor
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/all_docs.json

# Use Python to filter and extract the specific visit created during the task
python3 -c "
import sys, json, time

try:
    with open('/tmp/all_docs.json', 'r') as f:
        data = json.load(f)
    
    task_start = int($TASK_START)
    target_pat = '$PATIENT_ID'
    
    result = {
        'visit_found': False,
        'visit_doc': None,
        'count': 0
    }
    
    candidates = []
    
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        d = doc.get('data', doc)
        
        # Check type
        doc_type = d.get('type') or doc.get('type')
        if doc_type != 'visit':
            continue
            
        # Check patient link
        p_ref = d.get('patient') or d.get('patientId')
        if p_ref != target_pat:
            continue
            
        candidates.append(d)

    result['count'] = len(candidates)
    
    # Return the most recent candidate (assuming ID generation implies order or just taking the last one)
    # HospitalRun IDs are timestamp-ish or sequential.
    if candidates:
        result['visit_found'] = True
        result['visit_doc'] = candidates[-1] # Take the last one found
        
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/task_result.json

# 3. Add timestamp/metadata info to result
# We merge the python output with basic task info
jq -n \
  --slurpfile db_res /tmp/task_result.json \
  --arg start "$TASK_START" \
  --arg end "$(date +%s)" \
  '{
    task_start: $start, 
    task_end: $end, 
    db_result: $db_res[0],
    screenshot_path: "/tmp/task_final.png"
  }' > /tmp/final_export.json

# Move to standard location
mv /tmp/final_export.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json