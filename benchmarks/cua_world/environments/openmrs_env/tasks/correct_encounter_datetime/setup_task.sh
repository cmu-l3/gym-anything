#!/bin/bash
# Setup: Correct Encounter Timestamp
# Creates patient Arnulfo Kertzmann, a retrospective visit, and an incorrectly timestamped encounter.

set -e
echo "=== Setting up correct_encounter_datetime task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Ensure Patient Exists (Arnulfo Kertzmann)
PATIENT_NAME="Arnulfo Kertzmann"
echo "Locating patient: $PATIENT_NAME..."
PATIENT_UUID=$(get_patient_uuid "$PATIENT_NAME")

if [ -z "$PATIENT_UUID" ]; then
    echo "Patient not found, seeding..."
    # We use the seed script but filtered to ensuring this specific patient exists would be complex 
    # if the seed script is random. Instead, we create him manually via REST if not found.
    # For simplicity in this environment, we'll try the seed script first as it's deterministic 
    # for specific names in the provided context, or create a basic one.
    
    # Create Person
    PERSON_PAYLOAD='{
        "names": [{"givenName": "Arnulfo", "familyName": "Kertzmann", "preferred": true}],
        "gender": "M",
        "birthdate": "1980-01-01"
    }'
    PERSON_RESP=$(omrs_post "/person" "$PERSON_PAYLOAD")
    PERSON_UUID=$(echo "$PERSON_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
    
    # Create Patient
    if [ -n "$PERSON_UUID" ]; then
        # Generate ID (simulated or hardcoded for setup reliability if IDGEN fails)
        ID_TYPE="05a29f94-c0ed-11e2-94be-8c13b969e334" # OpenMRS ID
        LOCATION="44c3efb0-2583-4c80-a79e-1f756a03c0a1" # Outpatient Clinic
        
        # Try to generate ID via idgen
        GEN_ID=$(omrs_post "/idgen/identifiersource" '{"generateIdentifiers":true,"sourceUuid":"8549f706-7e85-4c1d-9424-217d50a2988b","numberToGenerate":1}' | \
                 python3 -c "import sys,json; print(json.load(sys.stdin).get('identifiers',[''])[0])")
        
        # Fallback ID if generator fails
        [ -z "$GEN_ID" ] && GEN_ID="100-9J" 
        
        PATIENT_PAYLOAD="{\"person\":\"$PERSON_UUID\",\"identifiers\":[{\"identifier\":\"$GEN_ID\",\"identifierType\":\"$ID_TYPE\",\"location\":\"$LOCATION\",\"preferred\":true}]}"
        PATIENT_RESP=$(omrs_post "/patient" "$PATIENT_PAYLOAD")
        PATIENT_UUID=$(echo "$PATIENT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
    fi
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Failed to create/locate patient."
    exit 1
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid.txt

# 2. Clean up previous data for this task (idempotency)
# We want to remove any existing encounters on Jan 15 2025 to start fresh
# (Script omits complex cleanup for brevity, assumes fresh env or handles duplicates)

# 3. Create Retrospective Visit (Jan 15, 2025)
VISIT_TYPE_UUID="7b0f5697-27e3-40c4-8bae-f4049abfb4ed" # Facility Visit
LOCATION_UUID="44c3efb0-2583-4c80-a79e-1f756a03c0a1" # Outpatient Clinic
VISIT_START="2025-01-15T08:00:00.000+0000"
VISIT_STOP="2025-01-15T16:00:00.000+0000"

VISIT_PAYLOAD="{\"patient\":\"$PATIENT_UUID\",\"visitType\":\"$VISIT_TYPE_UUID\",\"startDatetime\":\"$VISIT_START\",\"stopDatetime\":\"$VISIT_STOP\",\"location\":\"$LOCATION_UUID\"}"
VISIT_RESP=$(omrs_post "/visit" "$VISIT_PAYLOAD")
VISIT_UUID=$(echo "$VISIT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
echo "Visit UUID: $VISIT_UUID"

# 4. Create Incorrectly Timestamped Encounter (Vitals)
# "Incorrect" means: Linked to the past visit, but encounterDatetime is NOW (or close to now)
# indicating delayed entry.
VITALS_ENC_TYPE="67a71486-1a54-468f-ac3e-7091a9a79584"
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")

# Note: OpenMRS allows encounterDatetime to be outside visit range if configured loosely, 
# but usually it validates. If strictly validated, we set it to Visit Start, 
# but the task is to change it to specific time 14:00. 
# Let's set it to Visit Start (08:00) initially, so the agent has to change it to 14:00.
# OR better: The scenario implies "entered now". If validation prevents "now" (outside visit),
# we'll set it to 08:00 and ask agent to correct it to 14:00.
# Let's use 09:00 as the "wrong" time.
WRONG_TIME="2025-01-15T09:00:00.000+0000"

ENC_PAYLOAD="{\"patient\":\"$PATIENT_UUID\",\"visit\":\"$VISIT_UUID\",\"encounterType\":\"$VITALS_ENC_TYPE\",\"encounterDatetime\":\"$WRONG_TIME\",\"location\":\"$LOCATION_UUID\"}"
ENC_RESP=$(omrs_post "/encounter" "$ENC_PAYLOAD")
ENC_UUID=$(echo "$ENC_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
echo "Encounter UUID: $ENC_UUID"
echo "$ENC_UUID" > /tmp/task_encounter_uuid.txt

# Add some obs so it looks real (Weight = 80kg)
WEIGHT_CONCEPT="5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
OBS_PAYLOAD="{\"person\":\"$PATIENT_UUID\",\"encounter\":\"$ENC_UUID\",\"concept\":\"$WEIGHT_CONCEPT\",\"value\":80}"
omrs_post "/obs" "$OBS_PAYLOAD" > /dev/null

# 5. Launch Firefox
ensure_openmrs_logged_in "http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Visits"

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="