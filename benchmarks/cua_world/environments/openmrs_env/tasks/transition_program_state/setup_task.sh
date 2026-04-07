#!/bin/bash
# Setup: transition_program_state task
# Ensures Olen Bayer exists, is enrolled in "HIV Care and Treatment", and is currently in "Pre-ART" state.

echo "=== Setting up transition_program_state task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Find or Create Patient Olen Bayer
echo "Locating patient Olen Bayer..."
PATIENT_UUID=$(get_patient_uuid "Olen Bayer")

if [ -z "$PATIENT_UUID" ]; then
    echo "Creating patient Olen Bayer..."
    # Create via Python script logic (inline simplified version or call seeder)
    # We'll use a direct REST call sequence for precision here to ensure clean state
    
    # Generate ID
    ID_GEN=$(omrs_post "/idgen/identifiersource" '{"generateIdentifiers":true,"sourceUuid":"8549f706-7e85-4c1d-9424-217d50a2988b","numberToGenerate":1}' | python3 -c "import sys,json; print(json.load(sys.stdin)['identifiers'][0])")
    
    # Create Person
    PERSON_UUID=$(omrs_post "/person" '{"names":[{"givenName":"Olen","familyName":"Bayer"}],"gender":"M","birthdate":"1980-01-01","addresses":[{"address1":"123 Main St","cityVillage":"TestCity"}]}' | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])")
    
    # Create Patient
    PATIENT_UUID=$(omrs_post "/patient" "{\"person\":\"$PERSON_UUID\",\"identifiers\":[{\"identifier\":\"$ID_GEN\",\"identifierType\":\"05a29f94-c0ed-11e2-94be-8c13b969e334\",\"location\":\"44c3efb0-2583-4c80-a79e-1f756a03c0a1\",\"preferred\":true}]}" | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])")
fi
echo "Patient UUID: $PATIENT_UUID"

# 2. Get Program UUIDs
# HIV Care and Treatment Program UUID
PROGRAM_UUID=$(omrs_get "/program?q=HIV+Care+and+Treatment&v=default" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r['results'] else '')")

if [ -z "$PROGRAM_UUID" ]; then
    echo "ERROR: 'HIV Care and Treatment' program not found in metadata."
    exit 1
fi

# 3. Clean existing enrollments for this program
echo "Cleaning existing enrollments..."
EXISTING_ENROLLMENTS=$(omrs_get "/programenrollment?patient=$PATIENT_UUID&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(e['uuid']) for e in r.get('results',[]) if e['program']['uuid'] == '$PROGRAM_UUID']")

while IFS= read -r enroll_uuid; do
    if [ -n "$enroll_uuid" ]; then
        omrs_delete "/programenrollment/$enroll_uuid" > /dev/null
    fi
done <<< "$EXISTING_ENROLLMENTS"

# 4. Enroll patient in "Pre-ART" state (started 30 days ago)
echo "Enrolling patient in Pre-ART..."
PAST_DATE=$(date -d "30 days ago" -u +"%Y-%m-%dT%H:%M:%S.000+0000")

# We need the Workflow UUID and State UUID for "Pre-ART"
# This is tricky via REST search, so we assume standard CIEL/O3 metadata or fetch dynamically
# Fetch program full details to find the correct workflow/state UUIDs
PROGRAM_FULL=$(omrs_get "/program/$PROGRAM_UUID?v=full")

# Python script to extract the specific State UUID for "Pre-ART" inside "Treatment Status" workflow
PRE_ART_STATE_UUID=$(echo "$PROGRAM_FULL" | python3 -c "
import sys, json
data = json.load(sys.stdin)
target_state = ''
for workflow in data.get('allWorkflows', []):
    name = workflow.get('concept', {}).get('display', '')
    if 'Treatment Status' in name or 'Treatment status' in name:
        for state in workflow.get('states', []):
            s_name = state.get('concept', {}).get('display', '')
            if 'Pre-ART' in s_name:
                print(state['uuid'])
                sys.exit(0)
")

if [ -n "$PRE_ART_STATE_UUID" ]; then
    # Create enrollment with initial state
    # Note: O3 REST API for enrollment often takes 'states' array
    # Structure: states: [{state: uuid, startDate: date}]
    PAYLOAD=$(cat <<EOF
{
  "patient": "$PATIENT_UUID",
  "program": "$PROGRAM_UUID",
  "dateEnrolled": "$PAST_DATE",
  "location": "44c3efb0-2583-4c80-a79e-1f756a03c0a1",
  "states": [
    {
      "state": "$PRE_ART_STATE_UUID",
      "startDate": "$PAST_DATE"
    }
  ]
}
EOF
)
    omrs_post "/programenrollment" "$PAYLOAD" > /dev/null
    echo "Patient enrolled in HIV Care (Pre-ART)"
else
    echo "WARNING: Could not find Pre-ART state UUID. Enrolling without specific state."
    omrs_post "/programenrollment" "{\"patient\":\"$PATIENT_UUID\",\"program\":\"$PROGRAM_UUID\",\"dateEnrolled\":\"$PAST_DATE\",\"location\":\"44c3efb0-2583-4c80-a79e-1f756a03c0a1\"}" > /dev/null
fi

# 5. Launch Browser
echo "Launching Firefox..."
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="