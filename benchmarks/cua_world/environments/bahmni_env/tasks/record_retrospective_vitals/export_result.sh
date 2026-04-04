#!/bin/bash
echo "=== Exporting Retrospective Vitals Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Context Info
TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || date +%s)
TARGET_DATE_STR=$(cat /tmp/target_date.txt 2>/dev/null || date -d "10 days ago" '+%Y-%m-%d')
PATIENT_UUID=$(cat /tmp/patient_uuid.txt 2>/dev/null)
WEIGHT_CONCEPT="5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

if [ -z "$PATIENT_UUID" ]; then
    # Fallback lookup if temp file missing
    PATIENT_UUID=$(get_patient_uuid_by_identifier "BAH000015")
fi

echo "Fetching observations for Patient: $PATIENT_UUID"
echo "Target Date: $TARGET_DATE_STR"

# 3. Query OpenMRS for Weight Observations
# We fetch full details to check values, obsDatetime, and linked encounter
API_RESPONSE=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&concept=${WEIGHT_CONCEPT}&v=custom:(uuid,display,value,obsDatetime,dateCreated,encounter:(uuid,encounterDatetime))")

# 4. Process Result with Python
# We use Python to parse the JSON and find the *relevant* observation (value=82, created recently)
# and extract its details for the verifier.
python3 -c "
import sys, json, time
from datetime import datetime

try:
    api_data = json.load(sys.stdin)
    results = api_data.get('results', [])
    
    task_start_ts = $TASK_START_TS
    target_value = 82.0
    
    # Find the best candidate observation
    candidate = None
    
    for obs in results:
        # Check value (handle potential float/int diffs)
        try:
            val = float(obs.get('value', 0))
        except:
            continue
            
        if abs(val - target_value) < 0.1:
            # Check if created DURING the task (anti-gaming: don't count old records)
            # OpenMRS dateCreated format: 2023-10-25T10:00:00.000+0000
            created_str = obs.get('dateCreated', '')
            # Simple string parsing or fallback
            # We'll just pass all candidates to the verifier to make the logic robust there
            pass
            
    # We simply export the whole relevant list to the result JSON
    # and let the verifier script do the heavy lifting of date logic
    
    output = {
        'task_start_ts': task_start_ts,
        'target_date_str': '$TARGET_DATE_STR',
        'observations': results,
        'patient_uuid': '$PATIENT_UUID'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(output, f, indent=2)
        
except Exception as e:
    print(f'Error processing API response: {e}')
    # Create empty result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'observations': []}, f)
" <<< "$API_RESPONSE"

# 5. Fix Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Exported data to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="