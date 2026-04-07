#!/bin/bash
# Setup: edit_patient_name task
# Creates patient "Jonh Smithe" and opens their chart.

set -e
echo "=== Setting up edit_patient_name task ==="
source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming (verification checks modification time > start time)
date +%s > /tmp/task_start_timestamp

# 2. Cleanup: Delete any existing "John Smith" (the correct name) or "Jonh Smithe" (the wrong name)
# to ensure a clean start state.
echo "Cleaning up previous test data..."
# Search for target (correct) name
TARGET_UUIDS=$(omrs_get "/patient?q=John+Smith&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(p['uuid']) for p in r.get('results',[])]" 2>/dev/null || true)
for uuid in $TARGET_UUIDS; do
    [ -n "$uuid" ] && omrs_delete "/patient/$uuid" && echo "  Deleted existing 'John Smith' ($uuid)"
done

# Search for source (incorrect) name
SOURCE_UUIDS=$(omrs_get "/patient?q=Jonh+Smithe&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(p['uuid']) for p in r.get('results',[])]" 2>/dev/null || true)
for uuid in $SOURCE_UUIDS; do
    [ -n "$uuid" ] && omrs_delete "/patient/$uuid" && echo "  Deleted existing 'Jonh Smithe' ($uuid)"
done

# 3. Create the patient with the MISSPELLED name ("Jonh Smithe")
echo "Creating patient 'Jonh Smithe'..."

# Create Person
PERSON_PAYLOAD='{
    "names": [{"givenName": "Jonh", "familyName": "Smithe", "preferred": true}],
    "gender": "M",
    "birthdate": "1978-06-15",
    "addresses": [{
        "address1": "42 Industrial Pkwy",
        "cityVillage": "Springfield",
        "stateProvince": "MA",
        "country": "USA",
        "preferred": true
    }]
}'
PERSON_RESP=$(omrs_post "/person" "$PERSON_PAYLOAD")
PERSON_UUID=$(echo "$PERSON_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")

if [ -z "$PERSON_UUID" ]; then
    echo "ERROR: Failed to create person. Response: $PERSON_RESP"
    exit 1
fi

# Generate ID
ID_GEN_PAYLOAD='{"generateIdentifiers": true, "sourceUuid": "8549f706-7e85-4c1d-9424-217d50a2988b", "numberToGenerate": 1}'
ID_RESP=$(omrs_post "/idgen/identifiersource" "$ID_GEN_PAYLOAD")
OPENMRS_ID=$(echo "$ID_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('identifiers',[None])[0])")

if [ -z "$OPENMRS_ID" ] || [ "$OPENMRS_ID" == "None" ]; then
    echo "ERROR: Failed to generate OpenMRS ID."
    exit 1
fi

# Create Patient
PATIENT_PAYLOAD='{
    "person": "'"$PERSON_UUID"'",
    "identifiers": [{
        "identifier": "'"$OPENMRS_ID"'",
        "identifierType": "05a29f94-c0ed-11e2-94be-8c13b969e334",
        "location": "44c3efb0-2583-4c80-a79e-1f756a03c0a1",
        "preferred": true
    }]
}'
PATIENT_RESP=$(omrs_post "/patient" "$PATIENT_PAYLOAD")
PATIENT_UUID=$(echo "$PATIENT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Failed to create patient."
    exit 1
fi

echo "Created patient: Jonh Smithe ($PATIENT_UUID)"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid
echo "Jonh" > /tmp/initial_given_name
echo "Smithe" > /tmp/initial_family_name

# 4. Open Firefox on the patient's chart
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="