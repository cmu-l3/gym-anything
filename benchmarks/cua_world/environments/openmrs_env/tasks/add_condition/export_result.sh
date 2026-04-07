#!/bin/bash
# Export script for add_condition task
# Queries OpenMRS API to verify the condition was added correctly.

set -e
echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Inputs
PATIENT_UUID=$(cat /tmp/task_patient_uuid.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_condition_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query current conditions for the patient
echo "Fetching conditions for patient $PATIENT_UUID..."
API_RESPONSE=$(omrs_get "/condition?patientUuid=${PATIENT_UUID}&v=full")

# Process result with Python to extract verification data
# We check:
# 1. Total count
# 2. Presence of "Asthma"
# 3. Status of "Asthma" (Active vs Inactive)
# 4. Creation date of "Asthma" (must be > TASK_START)

python3 -c "
import sys, json, datetime

try:
    data = json.loads('''$API_RESPONSE''')
    results = data.get('results', [])
    
    current_count = len(results)
    initial_count = int('$INITIAL_COUNT')
    task_start = int('$TASK_START')
    
    asthma_found = False
    asthma_status = 'unknown'
    asthma_uuid = ''
    created_during_task = False
    date_created_iso = ''
    
    # Iterate to find Asthma
    for row in results:
        # Check condition name (coded or non-coded)
        cond_obj = row.get('condition', {})
        coded_name = cond_obj.get('coded', {}).get('display', '') or ''
        noncoded_name = cond_obj.get('nonCoded', '') or ''
        full_name = (coded_name + ' ' + noncoded_name).lower()
        
        if 'asthma' in full_name:
            asthma_found = True
            asthma_uuid = row.get('uuid')
            
            # Check status
            # Clinical status is usually an object: { 'display': 'Active', ... }
            status_obj = row.get('clinicalStatus', {})
            if isinstance(status_obj, dict):
                asthma_status = status_obj.get('display', 'unknown')
            else:
                asthma_status = str(status_obj)
            
            # Check creation time
            audit = row.get('auditInfo', {})
            date_created_iso = audit.get('dateCreated', '')
            # Simple timestamp check (OpenMRS returns ISO8601)
            # We trust the verifier.py to do precise parsing, passing the string here.
            # But we can do a rough check if needed.
            break

    output = {
        'initial_count': initial_count,
        'current_count': current_count,
        'asthma_found': asthma_found,
        'asthma_status': asthma_status,
        'asthma_uuid': asthma_uuid,
        'date_created_iso': date_created_iso,
        'task_start_ts': task_start,
        'patient_uuid': '$PATIENT_UUID'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(output, f, indent=2)

except Exception as e:
    print(f'Error processing JSON: {e}')
    # Write failure state
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)

"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="