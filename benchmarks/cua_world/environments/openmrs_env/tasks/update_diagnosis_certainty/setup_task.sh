#!/bin/bash
set -e
echo "=== Setting up update_diagnosis_certainty task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------------
# 1. Ensure Patient Exists (Ova Rau)
# -----------------------------------------------------------------------------
PATIENT_GIVEN="Ova"
PATIENT_FAMILY="Rau"
echo "Resolving patient: $PATIENT_GIVEN $PATIENT_FAMILY..."

PATIENT_UUID=$(get_patient_uuid "$PATIENT_GIVEN $PATIENT_FAMILY")

if [ -z "$PATIENT_UUID" ]; then
    echo "Patient not found. Creating..."
    # Create via Python script using the helper functions in seed_openmrs.py logic
    # We'll do a quick inline python script to create the patient via REST
    python3 -c "
import sys, json, requests
from datetime import date
auth = ('admin', 'Admin123')
base = 'http://localhost/openmrs/ws/rest/v1'

def get_json(url):
    return requests.get(base + url, auth=auth).json()

def post_json(url, data):
    return requests.post(base + url, json=data, auth=auth).json()

# 1. Person
person = post_json('/person', {
    'names': [{'givenName': '$PATIENT_GIVEN', 'familyName': '$PATIENT_FAMILY'}],
    'gender': 'F',
    'birthdate': '1985-04-12',
    'addresses': [{'address1': '123 Test St', 'cityVillage': 'Testville'}]
})
person_uuid = person['uuid']

# 2. ID Type & Location (hardcoded from standard O3 seed)
id_type = '05a29f94-c0ed-11e2-94be-8c13b969e334' # OpenMRS ID
location = '44c3efb0-2583-4c80-a79e-1f756a03c0a1' # Outpatient Clinic
source = '8549f706-7e85-4c1d-9424-217d50a2988b' # IDGen source

# Generate ID
gen_id = post_json('/idgen/identifiersource', {
    'generateIdentifiers': True, 
    'sourceUuid': source, 
    'numberToGenerate': 1
})['identifiers'][0]

# 3. Patient
patient = post_json('/patient', {
    'person': person_uuid,
    'identifiers': [{'identifier': gen_id, 'identifierType': id_type, 'location': location, 'preferred': True}]
})
print(patient['uuid'])
" > /tmp/new_patient_uuid.txt
    PATIENT_UUID=$(cat /tmp/new_patient_uuid.txt)
fi

echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid.txt

# -----------------------------------------------------------------------------
# 2. Ensure Active Visit
# -----------------------------------------------------------------------------
echo "Ensuring active visit..."
# Close any existing open visits to be clean
OPEN_VISITS=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(v['uuid']) for v in r.get('results',[]) if not v.get('stopDatetime')]" 2>/dev/null || true)

while IFS= read -r v_uuid; do
    if [ -n "$v_uuid" ]; then
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
        omrs_post "/visit/$v_uuid" "{\"stopDatetime\":\"$NOW\"}" > /dev/null || true
    fi
done <<< "$OPEN_VISITS"

# Create new visit
VISIT_TYPE_UUID="7b0f5697-27e3-40c4-8bae-f4049abfb4ed" # Facility Visit
LOCATION_UUID="44c3efb0-2583-4c80-a79e-1f756a03c0a1" # Outpatient Clinic
START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")

VISIT_RESP=$(omrs_post "/visit" "{
    \"patient\": \"$PATIENT_UUID\",
    \"visitType\": \"$VISIT_TYPE_UUID\",
    \"startDatetime\": \"$START_TIME\",
    \"location\": \"$LOCATION_UUID\"
}")
VISIT_UUID=$(echo "$VISIT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
echo "Active Visit UUID: $VISIT_UUID"

# -----------------------------------------------------------------------------
# 3. Seed "Presumed" Diagnosis (Anemia)
# -----------------------------------------------------------------------------
echo "Seeding diagnosis..."

# Find 'Anemia' concept
CONCEPT_UUID=$(omrs_get "/concept?q=Anemia&v=default" | python3 -c "
import sys, json
r = json.load(sys.stdin)
results = r.get('results', [])
# Prefer exact match or first result
uuid = next((c['uuid'] for c in results if c['display'].lower() == 'anemia'), results[0]['uuid'] if results else '')
print(uuid)
")

if [ -z "$CONCEPT_UUID" ]; then
    echo "ERROR: Could not find concept for Anemia"
    exit 1
fi
echo "Concept UUID for Anemia: $CONCEPT_UUID"

# Create Encounter with Diagnosis
# In O3/RefApp, diagnoses are often stored via the encounter endpoint.
# We create a 'Consultation' encounter containing the diagnosis.
ENC_TYPE_UUID="92fd09b4-5335-4f7e-9f63-b2b19f905086" # Consultation

# Note: The API structure for diagnoses depends on the module version, 
# but usually we can post an encounter with 'diagnoses' array or 'obs'.
# Here we use the standard core REST API pattern for diagnoses (if supported) 
# or fall back to SQL insertion if REST is tricky for specific diagnosis metadata.
# O3 Reference Application uses the 'encounter_diagnosis' table.

# Let's use SQL to insert the diagnosis directly to ensure it's in the correct state 'PRESUMED'
# and avoid REST API version complexity for this specific setup action.

# Get internal IDs
PATIENT_ID=$(omrs_db_query "SELECT patient_id FROM patient WHERE uuid='$PATIENT_UUID'")
VISIT_ID=$(omrs_db_query "SELECT visit_id FROM visit WHERE uuid='$VISIT_UUID'")
CONCEPT_ID=$(omrs_db_query "SELECT concept_id FROM concept WHERE uuid='$CONCEPT_UUID'")
ENCOUNTER_TYPE_ID=$(omrs_db_query "SELECT encounter_type_id FROM encounter_type WHERE uuid='$ENC_TYPE_UUID'")

# Create Encounter row
omrs_db_query "INSERT INTO encounter (encounter_type, patient_id, location_id, encounter_datetime, visit_id, date_created, creator, voided, uuid) VALUES ($ENCOUNTER_TYPE_ID, $PATIENT_ID, 2, NOW(), $VISIT_ID, NOW(), 1, 0, UUID());"
ENCOUNTER_ID=$(omrs_db_query "SELECT encounter_id FROM encounter WHERE visit_id=$VISIT_ID ORDER BY encounter_id DESC LIMIT 1")

# Create Encounter Diagnosis row (Presumed = 'PRESUMED', Confirmed = 'CONFIRMED')
omrs_db_query "INSERT INTO encounter_diagnosis (encounter_id, patient_id, diagnosis_coded_id, certainty, rank, date_created, creator, voided, uuid) VALUES ($ENCOUNTER_ID, $PATIENT_ID, $CONCEPT_ID, 'PRESUMED', 0, NOW(), 1, 0, UUID());"

echo "Seeded 'PRESUMED' Anemia diagnosis via DB (Encounter ID: $ENCOUNTER_ID)"

# -----------------------------------------------------------------------------
# 4. Prepare Browser
# -----------------------------------------------------------------------------
echo "Launching Firefox..."
TARGET_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"

ensure_openmrs_logged_in "$TARGET_URL"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="