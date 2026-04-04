#!/bin/bash
echo "=== Setting up Restore Patient Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Define Target Patient Details
TARGET_ID="BAH999999"
GIVEN_NAME="Deleted"
FAMILY_NAME="Patient"
GENDER="M"
BIRTHDATE="1980-01-01"

echo "Setting up target patient: $GIVEN_NAME $FAMILY_NAME ($TARGET_ID)"

# 1. Check if patient exists (even if voided)
# We use includeAll=true to find if they are already there
EXISTING_SEARCH=$(openmrs_api_get "/patient?q=${TARGET_ID}&v=full&includeAll=true")
PATIENT_UUID=$(echo "$EXISTING_SEARCH" | python3 -c "import sys, json; res = json.load(sys.stdin); print(res['results'][0]['uuid']) if res['results'] else print('')")

if [ -z "$PATIENT_UUID" ]; then
    echo "Patient does not exist. Creating..."
    
    # Need Location and Identifier Type
    LOC_UUID=$(openmrs_api_get "/location?v=default&limit=1" | python3 -c "import sys, json; print(json.load(sys.stdin)['results'][0]['uuid'])")
    ID_TYPE_UUID=$(openmrs_api_get "/patientidentifiertype?v=default" | python3 -c "import sys, json; res=json.load(sys.stdin); print([x['uuid'] for x in res['results'] if 'Patient Identifier' in x['display'] or 'Old Identification' in x['display']][0])")

    # Create Patient Payload
    PAYLOAD=$(cat <<EOF
{
  "person": {
    "names": [{"givenName": "$GIVEN_NAME", "familyName": "$FAMILY_NAME", "preferred": true}],
    "gender": "$GENDER",
    "birthdate": "$BIRTHDATE",
    "birthdateEstimated": false
  },
  "identifiers": [{
    "identifier": "$TARGET_ID",
    "identifierType": "$ID_TYPE_UUID",
    "location": "$LOC_UUID",
    "preferred": true
  }]
}
EOF
)
    CREATE_RESP=$(openmrs_api_post "/patient" "$PAYLOAD")
    PATIENT_UUID=$(echo "$CREATE_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uuid', ''))")
    
    if [ -z "$PATIENT_UUID" ]; then
        echo "ERROR: Failed to create patient"
        echo "Response: $CREATE_RESP"
        exit 1
    fi
    echo "Created patient with UUID: $PATIENT_UUID"
else
    echo "Patient already exists with UUID: $PATIENT_UUID"
    # Ensure name is correct (in case of re-use)
    # We won't update for now, assuming ID uniqueness implies identity
fi

# Save UUID for export script
echo "$PATIENT_UUID" > /tmp/target_patient_uuid.txt

# 2. Ensure Patient is VOIDED
echo "Ensuring patient is voided..."
# OpenMRS REST API: DELETE request to /patient/{uuid} voids the patient (unless purge=true)
# We use curl directly to handle the DELETE verb
VOID_RESP=$(curl -skS -X DELETE \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    "${OPENMRS_API_URL}/patient/${PATIENT_UUID}?reason=TaskSetupVoid")

# Verify void status
CHECK_RESP=$(openmrs_api_get "/patient/${PATIENT_UUID}?v=full&includeAll=true")
IS_VOIDED=$(echo "$CHECK_RESP" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('voided', False)).lower())")

if [ "$IS_VOIDED" != "true" ]; then
    echo "ERROR: Patient is not voided! Status: $IS_VOIDED"
    # Try explicitly setting voided via POST if DELETE didn't work as expected (OpenMRS version dependent)
    # Note: Generally DELETE is the standard way to void.
    exit 1
fi
echo "Patient is successfully voided."

# 3. Start Browser at Bahmni Home
echo "Starting browser..."
if ! start_browser "${BAHMNI_LOGIN_URL}"; then
    echo "WARNING: Browser failed to start, retrying..."
    start_browser "${BAHMNI_LOGIN_URL}"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="