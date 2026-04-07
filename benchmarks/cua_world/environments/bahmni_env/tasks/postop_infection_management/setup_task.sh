#!/bin/bash
set -e

echo "=== Setting up postop_infection_management task ==="

source /workspace/scripts/task_utils.sh

# -------------------------------------------------------------------
# 1. Delete stale outputs BEFORE recording timestamp
# -------------------------------------------------------------------
rm -f /tmp/pim_* 2>/dev/null || true
rm -f /tmp/postop_infection_management_result.json 2>/dev/null || true

# -------------------------------------------------------------------
# 2. Wait for Bahmni services to be ready
# -------------------------------------------------------------------
wait_for_bahmni 540

# -------------------------------------------------------------------
# 3. Record task start timestamp
# -------------------------------------------------------------------
date +%s > /tmp/pim_task_start_timestamp
date -u +"%Y-%m-%dT%H:%M:%S.000+0000" > /tmp/pim_start_time

# -------------------------------------------------------------------
# 4. Create patient BAH000025 (Grace Aiko Nakamura) if not exists
# -------------------------------------------------------------------
PATIENT_ID="BAH000025"
GIVEN_NAME="Grace"
MIDDLE_NAME="Aiko"
FAMILY_NAME="Nakamura"
GENDER="F"
DOB="1967-09-14"

echo "Checking if patient ${PATIENT_ID} exists..."
EXISTING=$(openmrs_api_get "/patient?identifier=${PATIENT_ID}&v=full")
PATIENT_COUNT=$(echo "$EXISTING" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))")

if [ "$PATIENT_COUNT" -gt "0" ]; then
    PATIENT_UUID=$(echo "$EXISTING" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][0]['uuid'])")
    echo "Patient already exists: $PATIENT_UUID"
else
    echo "Creating patient ${PATIENT_ID}..."

    # Get identifier type UUID (first non-Luhn-validated type)
    ID_TYPES=$(openmrs_api_get "/patientidentifiertype?v=full&limit=10")
    ID_TYPE_UUID=$(echo "$ID_TYPES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data.get('results', []):
    validator = t.get('validator', '') or ''
    if 'luhn' not in validator.lower():
        print(t['uuid'])
        break
")

    # Get location UUID
    LOCATION_UUID=$(openmrs_api_get "/location?tag=Login+Location&v=default" | python3 -c "
import sys, json
r = json.load(sys.stdin).get('results', [])
print(r[0]['uuid'] if r else '')
")

    PATIENT_PAYLOAD=$(python3 -c "
import json
payload = {
    'person': {
        'names': [{
            'givenName': '${GIVEN_NAME}',
            'middleName': '${MIDDLE_NAME}',
            'familyName': '${FAMILY_NAME}',
            'preferred': True
        }],
        'gender': '${GENDER}',
        'birthdate': '${DOB}',
        'birthdateEstimated': False,
        'addresses': [{
            'address1': '42 Riverside Drive',
            'cityVillage': 'Nairobi Central',
            'stateProvince': 'Nairobi',
            'country': 'Kenya'
        }]
    },
    'identifiers': [{
        'identifier': '${PATIENT_ID}',
        'identifierType': '${ID_TYPE_UUID}',
        'location': '${LOCATION_UUID}',
        'preferred': True
    }]
}
print(json.dumps(payload))
")

    RESULT=$(openmrs_api_post "/patient" "$PATIENT_PAYLOAD")
    PATIENT_UUID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
    echo "Created patient: $PATIENT_UUID"
fi

echo "$PATIENT_UUID" > /tmp/pim_patient_uuid
echo "$PATIENT_ID" > /tmp/pim_patient_identifier

# -------------------------------------------------------------------
# 5. Create active OPD visit (started 3 days ago, no stopDatetime)
# -------------------------------------------------------------------
echo "Setting up active visit..."

# Check for existing active visit
ACTIVE_VISITS=$(openmrs_api_get "/visit?patient=${PATIENT_UUID}&includeInactive=false&v=default")
ACTIVE_COUNT=$(echo "$ACTIVE_VISITS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('results',[])))")

if [ "$ACTIVE_COUNT" -gt "0" ]; then
    VISIT_UUID=$(echo "$ACTIVE_VISITS" | python3 -c "import sys,json; print(json.load(sys.stdin)['results'][0]['uuid'])")
    echo "Active visit already exists: $VISIT_UUID"
else
    # Get OPD visit type
    VISIT_TYPE_UUID=$(openmrs_api_get "/visittype?v=default" | python3 -c "
import sys, json
results = json.load(sys.stdin).get('results', [])
for vt in results:
    name = vt.get('name', '').lower()
    if 'opd' in name or 'outpatient' in name:
        print(vt['uuid'])
        break
else:
    if results:
        print(results[0]['uuid'])
")

    LOCATION_UUID=$(openmrs_api_get "/location?tag=Login+Location&v=default" | python3 -c "
import sys, json
r = json.load(sys.stdin).get('results', [])
print(r[0]['uuid'] if r else '')
")

    THREE_DAYS_AGO=$(date -u -d "3 days ago" +"%Y-%m-%dT%H:%M:%S.000+0000")

    VISIT_PAYLOAD=$(python3 -c "
import json
payload = {
    'patient': '${PATIENT_UUID}',
    'visitType': '${VISIT_TYPE_UUID}',
    'location': '${LOCATION_UUID}',
    'startDatetime': '${THREE_DAYS_AGO}'
}
print(json.dumps(payload))
")

    VISIT_RESULT=$(openmrs_api_post "/visit" "$VISIT_PAYLOAD")
    VISIT_UUID=$(echo "$VISIT_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
    echo "Created active visit: $VISIT_UUID"
fi

echo "$VISIT_UUID" > /tmp/pim_visit_uuid

# -------------------------------------------------------------------
# 6. Create historical encounter with admission vitals (3 days ago)
# -------------------------------------------------------------------
echo "Creating historical admission encounter with vitals..."

# Get encounter type (Consultation or first available)
ENC_TYPE_UUID=$(openmrs_api_get "/encountertype?v=default" | python3 -c "
import sys, json
results = json.load(sys.stdin).get('results', [])
for et in results:
    name = et.get('name', '').lower()
    if 'consultation' in name:
        print(et['uuid'])
        break
else:
    if results:
        print(results[0]['uuid'])
")

LOCATION_UUID=$(openmrs_api_get "/location?tag=Login+Location&v=default" | python3 -c "
import sys, json
r = json.load(sys.stdin).get('results', [])
print(r[0]['uuid'] if r else '')
")

# Use the same base time as the visit start, plus 1 hour to ensure it's within visit range
THREE_DAYS_AGO_ENC=$(date -u -d "3 days ago + 1 hour" +"%Y-%m-%dT%H:%M:%S.000+0000")

ENC_PAYLOAD=$(python3 -c "
import json
payload = {
    'patient': '${PATIENT_UUID}',
    'visit': '${VISIT_UUID}',
    'encounterType': '${ENC_TYPE_UUID}',
    'encounterDatetime': '${THREE_DAYS_AGO_ENC}',
    'location': '${LOCATION_UUID}',
    'obs': [
        {'concept': '5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'value': 37.8},
        {'concept': '5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'value': 88},
        {'concept': '5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'value': 126},
        {'concept': '5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'value': 78},
        {'concept': '5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'value': 64}
    ]
}
print(json.dumps(payload))
")

ENC_RESULT=$(openmrs_api_post "/encounter" "$ENC_PAYLOAD")
ENC_UUID=$(echo "$ENC_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
echo "Created historical encounter: $ENC_UUID"

# -------------------------------------------------------------------
# 7. Ensure required concepts exist in the dictionary
# -------------------------------------------------------------------
echo "Ensuring required concepts exist..."

# Helper: get class and datatype UUIDs
DRUG_CLASS_UUID=$(openmrs_api_get "/conceptclass?v=default" | python3 -c "
import sys, json
for c in json.load(sys.stdin).get('results', []):
    if c.get('name','').lower() == 'drug':
        print(c['uuid']); break
")

DIAGNOSIS_CLASS_UUID=$(openmrs_api_get "/conceptclass?v=default" | python3 -c "
import sys, json
for c in json.load(sys.stdin).get('results', []):
    if c.get('name','').lower() == 'diagnosis':
        print(c['uuid']); break
")

TEST_CLASS_UUID=$(openmrs_api_get "/conceptclass?v=default" | python3 -c "
import sys, json
for c in json.load(sys.stdin).get('results', []):
    if c.get('name','').lower() == 'test':
        print(c['uuid']); break
")

LABSET_CLASS_UUID=$(openmrs_api_get "/conceptclass?v=default" | python3 -c "
import sys, json
for c in json.load(sys.stdin).get('results', []):
    if c.get('name','').lower() == 'labset':
        print(c['uuid']); break
")

NA_DATATYPE_UUID=$(openmrs_api_get "/conceptdatatype?v=default" | python3 -c "
import sys, json
for d in json.load(sys.stdin).get('results', []):
    if 'n/a' in d.get('name','').lower():
        print(d['uuid']); break
")

NUMERIC_DATATYPE_UUID=$(openmrs_api_get "/conceptdatatype?v=default" | python3 -c "
import sys, json
for d in json.load(sys.stdin).get('results', []):
    if d.get('name','').lower() == 'numeric':
        print(d['uuid']); break
")

# Function to ensure a concept exists
ensure_concept() {
    local CONCEPT_NAME="$1"
    local CLASS_UUID="$2"
    local DATATYPE_UUID="$3"

    local SEARCH_RESULT
    SEARCH_RESULT=$(openmrs_api_get "/concept?q=$(echo "$CONCEPT_NAME" | sed 's/ /+/g')&v=default")
    local COUNT
    COUNT=$(echo "$SEARCH_RESULT" | python3 -c "
import sys, json
name_lower = '${CONCEPT_NAME}'.lower()
results = json.load(sys.stdin).get('results', [])
matches = [r for r in results if r.get('display','').lower() == name_lower]
print(len(matches))
")

    if [ "$COUNT" -eq "0" ]; then
        echo "  Creating concept: ${CONCEPT_NAME}"
        local PAYLOAD
        PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'names': [{'name': '${CONCEPT_NAME}', 'locale': 'en', 'conceptNameType': 'FULLY_SPECIFIED'}],
    'datatype': '${DATATYPE_UUID}',
    'conceptClass': '${CLASS_UUID}'
}))
")
        openmrs_api_post "/concept" "$PAYLOAD" > /dev/null 2>&1
    else
        echo "  Concept already exists: ${CONCEPT_NAME}"
    fi
}

ensure_concept "Ciprofloxacin" "$DRUG_CLASS_UUID" "$NA_DATATYPE_UUID"
ensure_concept "Appendicitis" "$DIAGNOSIS_CLASS_UUID" "$NA_DATATYPE_UUID"
ensure_concept "Wound Infection" "$DIAGNOSIS_CLASS_UUID" "$NA_DATATYPE_UUID"
ensure_concept "Complete Blood Count" "${LABSET_CLASS_UUID:-$TEST_CLASS_UUID}" "$NA_DATATYPE_UUID"
ensure_concept "C-Reactive Protein" "$TEST_CLASS_UUID" "$NUMERIC_DATATYPE_UUID"

# Ensure Ciprofloxacin drug entry exists
echo "Ensuring Ciprofloxacin drug entry exists..."
CIPRO_CONCEPT_UUID=$(openmrs_api_get "/concept?q=Ciprofloxacin&v=default" | python3 -c "
import sys, json
for r in json.load(sys.stdin).get('results', []):
    if r.get('display','').lower() == 'ciprofloxacin':
        print(r['uuid']); break
")

if [ -n "$CIPRO_CONCEPT_UUID" ]; then
    DRUG_SEARCH=$(openmrs_api_get "/drug?q=Ciprofloxacin&v=default")
    DRUG_COUNT=$(echo "$DRUG_SEARCH" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('results',[])))")
    if [ "$DRUG_COUNT" -eq "0" ]; then
        echo "  Creating drug entry: Ciprofloxacin 500mg Tablet"
        DRUG_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'name': 'Ciprofloxacin 500mg Tablet',
    'concept': '${CIPRO_CONCEPT_UUID}',
    'combination': False
}))
")
        openmrs_api_post "/drug" "$DRUG_PAYLOAD" > /dev/null 2>&1
    else
        echo "  Drug entry already exists: Ciprofloxacin"
    fi
fi

# -------------------------------------------------------------------
# 8. Record baseline counts for anti-gaming verification
# -------------------------------------------------------------------
echo "Recording baseline counts..."

INITIAL_ENC=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=custom:(uuid)" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('results',[])))")
echo "$INITIAL_ENC" > /tmp/pim_initial_encounter_count

INITIAL_OBS=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=custom:(uuid)" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('results',[])))")
echo "$INITIAL_OBS" > /tmp/pim_initial_obs_count

INITIAL_DRUG_ORDERS=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&v=custom:(uuid)" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('results',[])))")
echo "$INITIAL_DRUG_ORDERS" > /tmp/pim_initial_drug_order_count

INITIAL_TEST_ORDERS=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=testorder&v=custom:(uuid)" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('results',[])))")
echo "$INITIAL_TEST_ORDERS" > /tmp/pim_initial_test_order_count

# Allergy endpoint may return 500 on some OpenMRS versions; use MySQL as fallback
INITIAL_ALLERGIES=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "SELECT COUNT(*) FROM allergy WHERE patient_id = (SELECT patient_id FROM patient_identifier WHERE identifier = '${PATIENT_ID}' LIMIT 1) AND voided = 0;" 2>/dev/null || echo "0")
echo "$INITIAL_ALLERGIES" > /tmp/pim_initial_allergy_count

echo "Baselines: enc=$INITIAL_ENC obs=$INITIAL_OBS drug=$INITIAL_DRUG_ORDERS test=$INITIAL_TEST_ORDERS allergy=$INITIAL_ALLERGIES"

# -------------------------------------------------------------------
# 9. Launch browser to Bahmni login
# -------------------------------------------------------------------
echo "Launching browser..."
restart_firefox "${BAHMNI_LOGIN_URL}" 5

# -------------------------------------------------------------------
# 10. Take initial screenshot
# -------------------------------------------------------------------
take_screenshot /tmp/pim_task_start.png

echo "=== postop_infection_management task setup complete ==="
