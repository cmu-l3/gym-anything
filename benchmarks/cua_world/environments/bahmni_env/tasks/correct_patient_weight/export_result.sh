#!/bin/bash
echo "=== Exporting correct_patient_weight results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve the patient UUID saved during setup
if [ ! -f /tmp/target_patient_uuid.txt ]; then
    echo "ERROR: Target patient UUID file not found."
    PATIENT_UUID=""
else
    PATIENT_UUID=$(cat /tmp/target_patient_uuid.txt)
fi

# Query OpenMRS API for the patient's weight observations
# Concept UUID for Weight: 5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
WEIGHT_CONCEPT="5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
API_RESULT_FILE="/tmp/api_observations.json"

if [ -n "$PATIENT_UUID" ]; then
    echo "Querying observations for patient $PATIENT_UUID..."
    # We fetch v=full to see values and voided status (though API usually filters voided by default)
    curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/observation?patient=${PATIENT_UUID}&concept=${WEIGHT_CONCEPT}&v=full" \
        > "$API_RESULT_FILE"
else
    echo "{}" > "$API_RESULT_FILE"
fi

# Check if browser is running
APP_RUNNING="false"
if pgrep -f "epiphany" > /dev/null; then
    APP_RUNNING="true"
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os
import sys

try:
    with open('$API_RESULT_FILE', 'r') as f:
        obs_data = json.load(f)
    
    results = obs_data.get('results', [])
    active_weights = []
    
    for obs in results:
        # Check if observation is voided (should be false for active records)
        if obs.get('voided') is True:
            continue
            
        val = obs.get('value')
        # Handle numeric values
        try:
            val_float = float(val)
            active_weights.append(val_float)
        except (ValueError, TypeError):
            pass

    output = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'patient_uuid': '$PATIENT_UUID',
        'active_weights': active_weights,
        'app_running': '$APP_RUNNING' == 'true',
        'screenshot_exists': os.path.exists('/tmp/task_final.png')
    }
    
    print(json.dumps(output, indent=2))

except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="