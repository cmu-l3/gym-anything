#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query CouchDB for the result
# We look for a procedure document created for our patient
echo "Querying database for procedures..."

# We fetch all docs and filter in python to find the specific one
# We look for:
# - type: procedure
# - patient: patient_p1_000003
# - description: Laparoscopic Cholecystectomy
python3 -c "
import sys, json, re

try:
    # Load all docs from CouchDB
    import urllib.request
    with urllib.request.urlopen('${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true') as url:
        data = json.loads(url.read().decode())
    
    found_docs = []
    
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        # Flatten structure: HospitalRun puts fields in 'data' usually
        d = doc.get('data', doc)
        
        # Check if this is a procedure
        # Note: HospitalRun sometimes uses 'procedure' type or infers from fields
        doc_type = d.get('type', doc.get('type', ''))
        desc = d.get('description', d.get('procedureDescription', ''))
        patient = d.get('patient', '')
        visit = d.get('visit', '')
        
        # Match criteria
        is_procedure = (doc_type == 'procedure' or desc != '')
        is_correct_patient = ('patient_p1_000003' in patient)
        # Relaxed check for description to allow case variations
        is_correct_desc = ('laparoscopic' in desc.lower() and 'cholecystectomy' in desc.lower())
        
        if is_procedure and is_correct_patient and is_correct_desc:
            found_docs.append(d)

    # Output result
    result = {
        'found': len(found_docs) > 0,
        'count': len(found_docs),
        'docs': found_docs,
        'timestamp': '$(date +%s)'
    }
    
    print(json.dumps(result, indent=2))
    
except Exception as e:
    print(json.dumps({'error': str(e), 'found': False}))

" > /tmp/db_query_result.json

# 3. Compile Final JSON Report
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Read DB query result
DB_RESULT=$(cat /tmp/db_query_result.json)

# Create the final export structure
jq -n \
    --argjson db_result "$DB_RESULT" \
    --arg start_time "$TASK_START" \
    --arg end_time "$TASK_END" \
    --arg screenshot "/tmp/task_final.png" \
    '{
        task_start: $start_time,
        task_end: $end_time,
        database_check: $db_result,
        screenshot_path: $screenshot
    }' > /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="