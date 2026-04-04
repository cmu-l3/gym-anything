#!/bin/bash
set -e

echo "=== Exporting schedule_antenatal_care_series result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Fetch all appointments linked to the patient from CouchDB
# We export them to a JSON file for the python verifier to analyze
echo "Fetching appointments from database..."

# We use python to filter the _all_docs response because it's more robust than jq for complex logic
# and we want to handle the 'data' wrapper inconsistency of HospitalRun
python3 -c "
import sys, json, requests, time

couch_url = '${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true'
patient_id_segment = 'P-ANC-001'

try:
    response = requests.get(couch_url)
    data = response.json()
    
    appointments = []
    
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        # Extract the internal data object
        d = doc.get('data', doc)
        
        # Check type
        doc_type = d.get('type', doc.get('type', ''))
        
        # Check patient linkage (could be by ID 'patient_p1_...' or just ID string)
        patient_ref = d.get('patient', '')
        
        # Check if it's an appointment for our patient
        if doc_type == 'appointment' and (patient_id_segment in patient_ref or 'Fatima' in str(d)):
            # Normalize date fields
            start_date = d.get('startDate', d.get('date', ''))
            end_date = d.get('endDate', '')
            description = d.get('description', d.get('title', d.get('reason', '')))
            
            appointments.append({
                'id': doc.get('_id'),
                'rev': doc.get('_rev'),
                'startDate': start_date,
                'endDate': end_date,
                'description': description,
                'full_doc': d
            })
            
    result = {
        'appointments': appointments,
        'task_start_time': ${START_TIME},
        'timestamp': time.time()
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error exporting data: {e}')
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'appointments': []}, f)
"

# 4. Set permissions so the user/verifier can read it
chmod 644 /tmp/task_result.json

echo "Export complete. Found $(jq '.appointments | length' /tmp/task_result.json) appointments."