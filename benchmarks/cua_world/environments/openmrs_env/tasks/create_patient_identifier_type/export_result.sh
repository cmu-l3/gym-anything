#!/bin/bash
# Export: create_patient_identifier_type task
# Queries API for the created identifier type and exports details.

echo "=== Exporting create_patient_identifier_type results ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Query OpenMRS for the identifier type by name
echo "Querying for 'National ART Number'..."
API_RESPONSE=$(omrs_get "/patientidentifiertype?q=National+ART+Number&v=full")

# Extract details using Python
# We need to handle cases where it might not exist or multiple might match
python3 -c "
import sys, json, time

try:
    task_start = $TASK_START
    response = json.loads('''$API_RESPONSE''')
    results = response.get('results', [])
    
    # Find the exact match if multiple partial matches returned
    target = None
    for r in results:
        if r.get('name', '').strip() == 'National ART Number':
            target = r
            break
            
    found = False
    data = {}
    
    if target:
        found = True
        # Check creation time (auditInfo.dateCreated format: 2023-10-25T12:00:00.000+0000)
        # We'll just pass the raw string and handle parsing in verifier if needed, 
        # or compare existence here.
        
        # Extract fields
        data = {
            'uuid': target.get('uuid'),
            'name': target.get('name'),
            'description': target.get('description'),
            'required': target.get('required'),
            'uniquenessBehavior': target.get('uniquenessBehavior'), # UNIQUE, NON_UNIQUE, etc.
            'minLength': target.get('minLength'),
            'maxLength': target.get('maxLength'),
            'retired': target.get('retired'),
            'dateCreated': target.get('auditInfo', {}).get('dateCreated')
        }

    output = {
        'found': found,
        'data': data,
        'task_start_ts': task_start,
        'timestamp': time.time()
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(output, f, indent=2)
        
except Exception as e:
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'found': False, 'error': str(e)}, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="