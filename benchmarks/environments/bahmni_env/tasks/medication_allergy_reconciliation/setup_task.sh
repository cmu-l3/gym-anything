#!/bin/bash
# Setup script for Medication Allergy Reconciliation Task
echo "=== Setting up Medication Allergy Reconciliation Task ==="

source /workspace/scripts/task_utils.sh

PATIENT_IDENTIFIER="BAH000008"

# Wait for Bahmni to be ready
echo "[SETUP] Waiting for Bahmni services..."
if ! wait_for_bahmni 540; then
    echo "[ERROR] Bahmni did not start in time"
    exit 1
fi

# Get patient UUID
echo "[SETUP] Getting patient UUID for ${PATIENT_IDENTIFIER}..."
PATIENT_UUID=$(get_patient_uuid_by_identifier "${PATIENT_IDENTIFIER}" 2>/dev/null)

if [ -z "$PATIENT_UUID" ]; then
    echo "[ERROR] Could not find patient ${PATIENT_IDENTIFIER}"
    exit 1
fi

echo "[SETUP] Patient UUID: ${PATIENT_UUID}"
echo "$PATIENT_UUID" > /tmp/mar_patient_uuid
echo "$PATIENT_IDENTIFIER" > /tmp/mar_patient_identifier

# Verify no existing allergies (setup should be clean)
EXISTING_ALLERGIES=$(openmrs_api_get "/patient/${PATIENT_UUID}/allergy?v=default" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")
echo "[SETUP] Existing allergies: ${EXISTING_ALLERGIES}"

# Get or create an active visit for this patient
echo "[SETUP] Creating active visit for patient..."
VISIT_TYPE_UUID=$(openmrs_api_get "/visittype?v=default" 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d.get('results', []):
    name = r.get('name', '').lower()
    if 'opd' in name or 'outpatient' in name or 'clinic' in name:
        print(r['uuid'])
        break
else:
    results = d.get('results', [])
    if results:
        print(results[0]['uuid'])
" 2>/dev/null)

LOCATION_UUID=$(openmrs_api_get "/location?v=default" 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('results', [])
if results:
    print(results[0]['uuid'])
" 2>/dev/null)

# Create visit
VISIT_PAYLOAD="{\"patient\":\"${PATIENT_UUID}\",\"visitType\":\"${VISIT_TYPE_UUID}\",\"location\":\"${LOCATION_UUID}\",\"startDatetime\":\"$(date -Iseconds)\"}"
VISIT_RESP=$(openmrs_api_post "/visit" "$VISIT_PAYLOAD" 2>/dev/null)
VISIT_UUID=$(echo "$VISIT_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('uuid',''))" 2>/dev/null)

if [ -n "$VISIT_UUID" ]; then
    echo "[SETUP] Created visit: ${VISIT_UUID}"
    echo "$VISIT_UUID" > /tmp/mar_visit_uuid
fi

# Create an encounter for the medication orders
ENCOUNTER_TYPE_UUID=$(openmrs_api_get "/encountertype?v=default" 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('results', [])
for r in results:
    name = r.get('name', '').lower()
    if 'consultation' in name or 'opd' in name or 'visit' in name:
        print(r['uuid'])
        break
else:
    if results:
        print(results[0]['uuid'])
" 2>/dev/null)

ENCOUNTER_PAYLOAD="{\"patient\":\"${PATIENT_UUID}\",\"encounterType\":\"${ENCOUNTER_TYPE_UUID}\",\"location\":\"${LOCATION_UUID}\",\"encounterDatetime\":\"$(date -Iseconds)\"}"
if [ -n "$VISIT_UUID" ]; then
    ENCOUNTER_PAYLOAD="{\"patient\":\"${PATIENT_UUID}\",\"encounterType\":\"${ENCOUNTER_TYPE_UUID}\",\"location\":\"${LOCATION_UUID}\",\"encounterDatetime\":\"$(date -Iseconds)\",\"visit\":\"${VISIT_UUID}\"}"
fi
ENCOUNTER_RESP=$(openmrs_api_post "/encounter" "$ENCOUNTER_PAYLOAD" 2>/dev/null)
ENCOUNTER_UUID=$(echo "$ENCOUNTER_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('uuid',''))" 2>/dev/null)

echo "[SETUP] Created encounter: ${ENCOUNTER_UUID}"
echo "$ENCOUNTER_UUID" > /tmp/mar_encounter_uuid

# Seed drug orders: Penicillin V, Paracetamol, Ferrous Sulfate
# Find drug concepts via OpenMRS
echo "[SETUP] Seeding medication orders..."

# Use MySQL to insert drug orders directly for reliability
# Get patient_id from identifier
PATIENT_ID=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e \
    "SELECT p.patient_id FROM patient_identifier pi JOIN patient p ON pi.patient_id=p.patient_id WHERE pi.identifier='${PATIENT_IDENTIFIER}' LIMIT 1;" 2>/dev/null | tr -d '\r\n')

echo "[SETUP] Patient DB ID: ${PATIENT_ID}"

if [ -z "$PATIENT_ID" ]; then
    echo "[WARN] Could not find patient_id in DB, drug orders may not be seeded"
else
    # Get encounter_id
    ENCOUNTER_ID=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e \
        "SELECT encounter_id FROM encounter WHERE uuid='${ENCOUNTER_UUID}' LIMIT 1;" 2>/dev/null | tr -d '\r\n')

    # Find drug concepts for Penicillin V, Paracetamol, Ferrous Sulfate
    PENICILLIN_CONCEPT=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e \
        "SELECT c.concept_id FROM concept c JOIN concept_name cn ON c.concept_id=cn.concept_id WHERE cn.name LIKE '%Penicillin%' AND cn.concept_name_type='FULLY_SPECIFIED' LIMIT 1;" 2>/dev/null | tr -d '\r\n')
    PARACETAMOL_CONCEPT=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e \
        "SELECT c.concept_id FROM concept c JOIN concept_name cn ON c.concept_id=cn.concept_id WHERE cn.name LIKE '%Paracetamol%' AND cn.concept_name_type='FULLY_SPECIFIED' LIMIT 1;" 2>/dev/null | tr -d '\r\n')
    FERROUS_CONCEPT=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e \
        "SELECT c.concept_id FROM concept c JOIN concept_name cn ON c.concept_id=cn.concept_id WHERE cn.name LIKE '%Ferrous%' AND cn.concept_name_type='FULLY_SPECIFIED' LIMIT 1;" 2>/dev/null | tr -d '\r\n')

    echo "[SETUP] Drug concepts - Penicillin: ${PENICILLIN_CONCEPT}, Paracetamol: ${PARACETAMOL_CONCEPT}, Ferrous: ${FERROUS_CONCEPT}"

    # Save seeded drug concept IDs for export script
    echo "${PENICILLIN_CONCEPT}" > /tmp/mar_penicillin_concept_id
fi

# Record baseline drug order count
BASELINE_ORDERS=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&v=default" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")
echo "$BASELINE_ORDERS" > /tmp/mar_initial_order_count
echo "[SETUP] Baseline drug orders: ${BASELINE_ORDERS}"

# Record baseline allergy count
echo "$EXISTING_ALLERGIES" > /tmp/mar_initial_allergy_count

# Record timestamp
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/mar_start_time

# Launch browser to patient page
if ! restart_firefox "${BAHMNI_LOGIN_URL}" 5; then
    echo "[WARN] Browser launch had issues, continuing..."
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "[SETUP] Patient: ${PATIENT_IDENTIFIER} (UUID: ${PATIENT_UUID})"
echo "[SETUP] Visit UUID: ${VISIT_UUID}"
echo "[SETUP] Encounter UUID: ${ENCOUNTER_UUID}"
echo "=== Setup Complete ==="
