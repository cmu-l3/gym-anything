#!/bin/bash
# Setup script for add_condition task
# Selects a patient without Asthma, records initial state, and navigates to chart.

set -e
echo "=== Setting up add_condition task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Find a suitable patient (one who does NOT have Asthma)
echo "Finding suitable patient..."
PATIENT_UUID=""
PATIENT_NAME=""

# Get first 10 patients
PATIENTS=$(omrs_get "/patient?v=default&limit=10" | python3 -c "import sys,json; print(' '.join([p['uuid'] for p in json.load(sys.stdin).get('results',[])]))" 2>/dev/null)

for uuid in $PATIENTS; do
    # Check existing conditions
    HAS_ASTHMA=$(omrs_get "/condition?patientUuid=$uuid&v=default" | python3 -c "
import sys, json
data = json.load(sys.stdin)
found = False
for res in data.get('results', []):
    cond = res.get('condition', {}).get('coded', {}).get('display', '') or ''
    if 'asthma' in cond.lower():
        found = True
        break
print('yes' if found else 'no')
" 2>/dev/null)

    if [ "$HAS_ASTHMA" == "no" ]; then
        PATIENT_UUID="$uuid"
        PATIENT_NAME=$(omrs_get "/patient/$uuid?v=default" | python3 -c "import sys,json; print(json.load(sys.stdin).get('person',{}).get('display','Patient'))" 2>/dev/null)
        break
    fi
done

# Fallback: if all have Asthma, pick the first one and delete the condition
if [ -z "$PATIENT_UUID" ]; then
    PATIENT_UUID=$(echo $PATIENTS | awk '{print $1}')
    PATIENT_NAME=$(omrs_get "/patient/$PATIENT_UUID?v=default" | python3 -c "import sys,json; print(json.load(sys.stdin).get('person',{}).get('display','Patient'))" 2>/dev/null)
    echo "Clearing existing Asthma conditions for $PATIENT_NAME..."
    
    # Get condition UUIDs
    COND_UUIDS=$(omrs_get "/condition?patientUuid=$PATIENT_UUID&v=default" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for res in data.get('results', []):
    cond = res.get('condition', {}).get('coded', {}).get('display', '') or ''
    if 'asthma' in cond.lower():
        print(res['uuid'])
" 2>/dev/null)
    
    for cond_uuid in $COND_UUIDS; do
        omrs_delete "/condition/$cond_uuid"
    done
fi

echo "Selected Patient: $PATIENT_NAME ($PATIENT_UUID)"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid.txt
echo "$PATIENT_NAME" > /tmp/task_patient_name.txt

# 3. Record initial count of conditions
INITIAL_COUNT=$(omrs_get "/condition?patientUuid=$PATIENT_UUID&v=default" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('results',[])))" 2>/dev/null)
echo "$INITIAL_COUNT" > /tmp/initial_condition_count.txt
echo "Initial condition count: $INITIAL_COUNT"

# 4. Launch Firefox and navigate to Patient Chart
# We go to the "Conditions" tab specifically to assist the agent, or just the main chart
CHART_URL="http://localhost/openmrs/spa/patient/${PATIENT_UUID}/chart/Conditions"

echo "Navigating to $CHART_URL..."
ensure_openmrs_logged_in "$CHART_URL"

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="