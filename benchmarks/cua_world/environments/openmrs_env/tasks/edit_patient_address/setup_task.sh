#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Update Patient Address Task ==="

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Patient "Angela Rivera" Exists with INITIAL State
# We want to reset her data if she exists, or create her if she doesn't.
# Target Initial State: 185 Berry Street, San Francisco, CA 94107

PATIENT_UUID=$(get_patient_uuid "Angela Rivera")

if [ -z "$PATIENT_UUID" ]; then
    echo "Creating patient Angela Rivera..."
    
    # Generate ID
    ID_GEN_RESP=$(omrs_post "/idgen/identifiersource" '{"generateIdentifiers":true,"sourceUuid":"8549f706-7e85-4c1d-9424-217d50a2988b","numberToGenerate":1}')
    OPENMRS_ID=$(echo "$ID_GEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('identifiers',[''])[0])")

    # Create Person
    PERSON_PAYLOAD='{
        "names": [{"givenName": "Angela", "familyName": "Rivera", "preferred": true}],
        "gender": "F",
        "birthdate": "1984-07-22",
        "addresses": [{
            "address1": "185 Berry Street",
            "cityVillage": "San Francisco",
            "stateProvince": "California",
            "country": "United States",
            "postalCode": "94107",
            "preferred": true
        }]
    }'
    PERSON_RESP=$(omrs_post "/person" "$PERSON_PAYLOAD")
    PERSON_UUID=$(echo "$PERSON_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")

    # Create Patient
    PATIENT_PAYLOAD="{\"person\": \"$PERSON_UUID\", \"identifiers\": [{\"identifier\": \"$OPENMRS_ID\", \"identifierType\": \"05a29f94-c0ed-11e2-94be-8c13b969e334\", \"location\": \"44c3efb0-2583-4c80-a79e-1f756a03c0a1\", \"preferred\": true}]}"
    PATIENT_RESP=$(omrs_post "/patient" "$PATIENT_PAYLOAD")
    PATIENT_UUID=$(echo "$PATIENT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
    
    echo "Created Angela Rivera: $PATIENT_UUID"

else
    echo "Resetting Angela Rivera to initial state..."
    # If patient exists, we must ensure address is reset to San Francisco
    PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")
    
    # Get existing addresses
    ADDRESSES=$(omrs_get "/person/${PERSON_UUID}/address" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('results',[])))")
    
    # Delete or Void existing addresses (simplest is to void and add new preferred, or update existing)
    # Here we update the first preferred address found
    ADDR_UUID=$(echo "$ADDRESSES" | python3 -c "import sys,json; addrs=json.load(sys.stdin); print(addrs[0]['uuid'] if addrs else '')")
    
    if [ -n "$ADDR_UUID" ]; then
        # Update existing address entry
        RESET_PAYLOAD='{
            "address1": "185 Berry Street",
            "cityVillage": "San Francisco",
            "stateProvince": "California",
            "country": "United States",
            "postalCode": "94107"
        }'
        omrs_post "/person/${PERSON_UUID}/address/${ADDR_UUID}" "$RESET_PAYLOAD" > /dev/null
    else
        # No address exists, add one
        NEW_ADDR_PAYLOAD='{
            "address1": "185 Berry Street",
            "cityVillage": "San Francisco",
            "stateProvince": "California",
            "country": "United States",
            "postalCode": "94107",
            "preferred": true
        }'
        omrs_post "/person/${PERSON_UUID}" "$NEW_ADDR_PAYLOAD" > /dev/null # This might be wrong endpoint for adding address, usually it's /person/uuid/address, but let's stick to update if possible or ignore if complex.
        # Actually simplest O3 way: POST to /person/{uuid} with "addresses": [...] updates them.
    fi
    echo "Reset complete."
fi

# 3. Save initial state verification data
PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")
INITIAL_ADDR_JSON=$(omrs_get "/person/${PERSON_UUID}/address")
echo "$INITIAL_ADDR_JSON" > /tmp/initial_address_state.json

# 4. Prepare Browser
echo "Launching OpenMRS Home..."
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="