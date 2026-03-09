#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query CouchDB for Operative Plans created after start time
# looking for the specific one we asked for
echo "Querying database for new operative plans..."

# We fetch all docs and filter in Python to be robust against schema variations
# HospitalRun creates docs with IDs like "operativePlan_..."
DB_DUMP_FILE="/tmp/db_dump.json"
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > "$DB_DUMP_FILE"

# Extract relevant document
python3 -c "
import sys, json, re

task_start = int($TASK_START)
target_patient = 'patient_p1_000002' # Ahmed Hassan Ali

try:
    with open('$DB_DUMP_FILE', 'r') as f:
        data = json.load(f)
        
    found_plans = []
    
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        d = doc.get('data', doc) # HospitalRun often nests in 'data'
        
        # Check basic type/structure
        # ID usually starts with operativePlan or type field is operativePlan
        doc_id = row.get('id', '')
        doc_type = d.get('type', doc.get('type', ''))
        
        is_op_plan = 'operativePlan' in doc_id or doc_type == 'operativePlan'
        if not is_op_plan:
            # Fallback: check keys
            if 'operationDescription' in d or 'surgeon' in d:
                is_op_plan = True
                
        if is_op_plan:
            # Check patient linkage
            patient_ref = d.get('patient', doc.get('patient', ''))
            
            # Check content matches our target
            op_desc = d.get('operationDescription', '')
            surgeon = d.get('surgeon', '')
            
            # Check if this looks like our target doc
            if target_patient in patient_ref:
                found_plans.append({
                    'id': doc_id,
                    'operation': op_desc,
                    'surgeon': surgeon,
                    'complexity': d.get('complexity', ''),
                    'status': d.get('status', ''),
                    'notes': d.get('additionalNotes', ''),
                    'instructions': d.get('admissionInstructions', ''),
                    # HospitalRun doesn't always timestamp docs reliably in metadata,
                    # so we primarily rely on it being present now vs deleted in setup.
                    # But we can check metadata if available.
                    'created_at': d.get('date', d.get('operationDate', ''))
                })

    result = {
        'task_start': task_start,
        'plans_found': found_plans,
        'screenshot_exists': True
    }
    
    with open('/tmp/task_result.json', 'w') as out:
        json.dump(result, out, indent=2)
        
except Exception as e:
    print(f'Error processing DB dump: {e}')
    with open('/tmp/task_result.json', 'w') as out:
        json.dump({'error': str(e)}, out)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result export complete:"
cat /tmp/task_result.json