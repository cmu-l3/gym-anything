#!/bin/bash
# Setup: reassign_encounter_provider task
# 1. Creates Provider "Dr. Cordelia Clinician"
# 2. Creates Patient "Michael Audit"
# 3. Creates a retrospective Visit & Vitals Encounter (2024-01-01) assigned to Admin
# 4. Launches Firefox on the patient's chart

set -e
echo "=== Setting up reassign_encounter_provider task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------
# 1. Create the Correct Provider: Dr. Cordelia Clinician
# ---------------------------------------------------------
echo "Creating provider: Dr. Cordelia Clinician..."

# Check if person exists, else create
EXISTING_PERSON=$(omrs_get "/person?q=Cordelia+Clinician&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r['results'] else '')" 2>/dev/null || true)

if [ -z "$EXISTING_PERSON" ]; then
    PERSON_PAYLOAD='{
        "names": [{"givenName": "Cordelia", "familyName": "Clinician"}],
        "gender": "F",
        "birthdate": "1980-01-01"
    }'
    EXISTING_PERSON=$(omrs_post "/person" "$PERSON_PAYLOAD" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || true)
fi

# Create Provider linked to Person (if not exists)
CORRECT_PROVIDER_UUID=$(omrs_get "/provider?q=Cordelia&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r['results'] else '')" 2>/dev/null || true)

if [ -z "$CORRECT_PROVIDER_UUID" ]; then
    PROV_PAYLOAD="{\"person\": \"$EXISTING_PERSON\", \"identifier\": \"DOC-CORDELIA\"}"
    CORRECT_PROVIDER_UUID=$(omrs_post "/provider" "$PROV_PAYLOAD" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || true)
fi
echo "Target Provider UUID: $CORRECT_PROVIDER_UUID"

# Get Admin Provider UUID (the "Bad" provider)
ADMIN_PROVIDER_UUID=$(omrs_get "/provider?q=admin&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r['results'] else '')" 2>/dev/null || true)
echo "Initial (Bad) Provider UUID: $ADMIN_PROVIDER_UUID"

# ---------------------------------------------------------
# 2. Create the Patient: Michael Audit
# ---------------------------------------------------------
echo "Creating patient: Michael Audit..."
PATIENT_UUID=$(get_patient_uuid "Michael Audit")

if [ -z "$PATIENT_UUID" ]; then
    # Create Person
    P_PAYLOAD='{
        "names": [{"givenName": "Michael", "familyName": "Audit"}],
        "gender": "M",
        "birthdate": "1960-06-15",
        "addresses": [{"address1": "123 Audit Ln", "cityVillage": "Review City"}]
    }'
    P_UUID=$(omrs_post "/person" "$P_PAYLOAD" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || true)
    
    # Generate ID
    ID_GEN=$(omrs_post "/idgen/identifiersource" '{"generateIdentifiers":true,"sourceUuid":"8549f706-7e85-4c1d-9424-217d50a2988b","numberToGenerate":1}' | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r['identifiers'][0] if r.get('identifiers') else '')" 2>/dev/null || true)
    
    # Create Patient
    PAT_PAYLOAD="{\"person\": \"$P_UUID\", \"identifiers\": [{\"identifier\": \"$ID_GEN\", \"identifierType\": \"05a29f94-c0ed-11e2-94be-8c13b969e334\", \"location\": \"44c3efb0-2583-4c80-a79e-1f756a03c0a1\", \"preferred\": true}]}"
    PATIENT_UUID=$(omrs_post "/patient" "$PAT_PAYLOAD" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || true)
fi
echo "Patient UUID: $PATIENT_UUID"

# ---------------------------------------------------------
# 3. Create Retrospective Visit & Encounter
# ---------------------------------------------------------
echo "Creating retrospective data..."

# Constants
VISIT_TYPE_UUID="7b0f5697-27e3-40c4-8bae-f4049abfb4ed" # Facility Visit
ENC_TYPE_UUID="67a71486-1a54-468f-ac3e-7091a9a79584"   # Vitals
ENC_ROLE_UUID="240b26f9-dd88-4172-823d-4a8bfeb7841f"   # Unknown Role (default) or Clinician

DATE="2024-01-01"
START_DT="${DATE}T10:00:00.000+0000"
STOP_DT="${DATE}T11:00:00.000+0000"

# Check if visit exists to avoid dups on re-run
EXISTING_VISIT=$(omrs_get "/visit?patient=$PATIENT_UUID&fromStartDate=$DATE&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)

if [ -z "$EXISTING_VISIT" ]; then
    V_PAYLOAD="{\"patient\": \"$PATIENT_UUID\", \"visitType\": \"$VISIT_TYPE_UUID\", \"startDatetime\": \"$START_DT\", \"stopDatetime\": \"$STOP_DT\", \"location\": \"44c3efb0-2583-4c80-a79e-1f756a03c0a1\"}"
    EXISTING_VISIT=$(omrs_post "/visit" "$V_PAYLOAD" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || true)
fi
echo "Visit UUID: $EXISTING_VISIT"

# Create Encounter assigned to ADMIN (The error state)
E_PAYLOAD="{
    \"patient\": \"$PATIENT_UUID\",
    \"visit\": \"$EXISTING_VISIT\",
    \"encounterType\": \"$ENC_TYPE_UUID\",
    \"encounterDatetime\": \"$START_DT\",
    \"encounterProviders\": [
        {
            \"provider\": \"$ADMIN_PROVIDER_UUID\",
            \"encounterRole\": \"$ENC_ROLE_UUID\"
        }
    ],
    \"obs\": [
        {\"concept\": \"5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\", \"value\": 70} 
    ]
}"
# Note: 5089 is Weight

ENCOUNTER_UUID=$(omrs_post "/encounter" "$E_PAYLOAD" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || true)

echo "Encounter UUID: $ENCOUNTER_UUID"

# ---------------------------------------------------------
# 4. Save Task Context for Export Script
# ---------------------------------------------------------
cat > /tmp/reassign_provider_context.json <<EOF
{
    "patient_uuid": "$PATIENT_UUID",
    "target_encounter_uuid": "$ENCOUNTER_UUID",
    "correct_provider_uuid": "$CORRECT_PROVIDER_UUID",
    "bad_provider_uuid": "$ADMIN_PROVIDER_UUID"
}
EOF

# ---------------------------------------------------------
# 5. Launch Browser
# ---------------------------------------------------------
# Navigate to Patient Chart -> Visits
URL="http://localhost/openmrs/spa/patient/${PATIENT_UUID}/chart/Visits"
ensure_openmrs_logged_in "$URL"

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="