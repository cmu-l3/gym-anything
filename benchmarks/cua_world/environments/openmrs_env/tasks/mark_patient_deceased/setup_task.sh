#!/bin/bash
# Setup: mark_patient_deceased
# Ensures Harold Bergstrom exists and is currently marked as ALIVE.

echo "=== Setting up mark_patient_deceased task ==="
source /workspace/scripts/task_utils.sh

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 1. Check if patient exists, otherwise create him
GIVEN="Harold"
FAMILY="Bergstrom"
FULL_NAME="$GIVEN $FAMILY"

echo "Checking for patient: $FULL_NAME..."
PATIENT_UUID=$(get_patient_uuid "$FULL_NAME")

if [ -z "$PATIENT_UUID" ]; then
    echo "Creating patient $FULL_NAME..."
    # 1. Create Person
    PERSON_PAYLOAD='{
        "names": [{"givenName": "'"$GIVEN"'", "familyName": "'"$FAMILY"'", "preferred": true}],
        "gender": "M",
        "birthdate": "1948-07-22",
        "addresses": [{
            "address1": "742 Industrial Blvd",
            "cityVillage": "Springfield",
            "stateProvince": "Illinois",
            "country": "USA",
            "postalCode": "62704",
            "preferred": true
        }]
    }'
    PERSON_RESP=$(omrs_post "/person" "$PERSON_PAYLOAD")
    PERSON_UUID=$(echo "$PERSON_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")

    if [ -z "$PERSON_UUID" ]; then
        echo "ERROR: Failed to create person."
        exit 1
    fi

    # 2. Get ID Type and Location (hardcoded from standard RefApp or fetched)
    ID_TYPE="05a29f94-c0ed-11e2-94be-8c13b969e334" # OpenMRS ID
    LOCATION="44c3efb0-2583-4c80-a79e-1f756a03c0a1" # Unknown Location
    
    # 3. Generate Identifier
    ID_GEN_SOURCE="8549f706-7e85-4c1d-9424-217d50a2988b"
    GEN_ID=$(omrs_post "/idgen/identifiersource" '{"generateIdentifiers": true, "sourceUuid": "'"$ID_GEN_SOURCE"'", "numberToGenerate": 1}' | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('identifiers',[None])[0])")

    # 4. Create Patient
    PATIENT_PAYLOAD='{
        "person": "'"$PERSON_UUID"'",
        "identifiers": [{
            "identifier": "'"$GEN_ID"'",
            "identifierType": "'"$ID_TYPE"'",
            "location": "'"$LOCATION"'",
            "preferred": true
        }]
    }'
    PATIENT_RESP=$(omrs_post "/patient" "$PATIENT_PAYLOAD")
    PATIENT_UUID=$(echo "$PATIENT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Could not find or create patient."
    exit 1
fi

echo "Target Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/target_patient_uuid.txt

# 2. Reset state: Ensure patient is ALIVE (dead=false, deathDate=null)
echo "Resetting patient state to ALIVE..."
PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")
# We use the REST API to un-kill them if they were dead
omrs_post "/person/$PERSON_UUID" '{"dead": false, "deathDate": null, "causeOfDeath": null}' > /dev/null

# 3. Verify Initial State (via DB for robustness)
INITIAL_STATE_JSON=$(omrs_db_query "SELECT dead, death_date FROM person WHERE uuid='$PERSON_UUID'")
echo "Initial DB State: $INITIAL_STATE_JSON"

# 4. Open Firefox to Home Page
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 5. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="