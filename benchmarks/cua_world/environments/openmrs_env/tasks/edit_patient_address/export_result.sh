#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_UUID=$(get_patient_uuid "Angela Rivera")

RESULT_JSON="/tmp/task_result.json"

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Patient Angela Rivera not found!"
    # Create failure result
    cat > "$RESULT_JSON" << EOF
{
    "patient_found": false,
    "task_start_time": $START_TIME
}
EOF
    exit 0
fi

PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")

# 3. Fetch Current Address Data via REST API
# OpenMRS REST API /person/{uuid}/address provides the address entries
ADDRESS_DATA=$(omrs_get "/person/${PERSON_UUID}/address?v=full")

# 4. Fetch Audit Info (to check modification times)
# The 'v=full' in address above usually includes auditInfo (dateCreated, dateChanged)

# 5. Construct Result JSON
# We use Python to parse the API response and extract the preferred address
python3 -c "
import sys, json, time

try:
    data = json.loads('''$ADDRESS_DATA''')
    results = data.get('results', [])
    
    # Find preferred address
    preferred = next((a for a in results if a.get('preferred')), results[0] if results else None)
    
    output = {
        'patient_found': True,
        'patient_uuid': '$PATIENT_UUID',
        'task_start_time': $START_TIME,
        'addresses': results,
        'preferred_address': preferred,
        'timestamp': time.time()
    }
    
    print(json.dumps(output))
except Exception as e:
    print(json.dumps({'error': str(e), 'patient_found': False}))
" > "$RESULT_JSON"

# 6. Set Permissions for Verifier
chmod 666 "$RESULT_JSON"
chmod 666 /tmp/task_final.png

echo "Export complete. Result saved to $RESULT_JSON"