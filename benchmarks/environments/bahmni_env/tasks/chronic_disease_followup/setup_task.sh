#!/bin/bash
# Setup script for Chronic Disease Follow-up Task
echo "=== Setting up Chronic Disease Follow-up Task ==="

source /workspace/scripts/task_utils.sh

PATIENT_IDENTIFIER="BAH000022"
PATIENT_GIVEN="Mohammed"
PATIENT_FAMILY="Al-Rashidi"
PATIENT_DOB="1975-03-15"
PATIENT_GENDER="M"

# Wait for Bahmni to be ready
echo "[SETUP] Waiting for Bahmni services..."
if ! wait_for_bahmni 540; then
    echo "[ERROR] Bahmni did not start in time"
    exit 1
fi

# Check if patient already exists
echo "[SETUP] Checking if patient ${PATIENT_IDENTIFIER} exists..."
EXISTING=$(openmrs_api_get "/patient?identifier=${PATIENT_IDENTIFIER}&v=default" 2>/dev/null)
EXISTING_COUNT=$(echo "$EXISTING" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")

if [ "$EXISTING_COUNT" -eq "0" ]; then
    echo "[SETUP] Creating patient ${PATIENT_IDENTIFIER}..."

    # Get identifier type UUID
    ID_TYPE_RESP=$(openmrs_api_get "/patientidentifiertype?v=default" 2>/dev/null)
    ID_TYPE_UUID=$(echo "$ID_TYPE_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d.get('results', []):
    if 'bahmni' in r.get('name','').lower() or 'patient id' in r.get('name','').lower() or 'identifier' in r.get('name','').lower():
        print(r['uuid'])
        break
" 2>/dev/null)

    # Fallback: get first identifier type
    if [ -z "$ID_TYPE_UUID" ]; then
        ID_TYPE_UUID=$(echo "$ID_TYPE_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('results', [])
if results:
    print(results[0]['uuid'])
" 2>/dev/null)
    fi

    # Create patient via OpenMRS REST
    PATIENT_PAYLOAD=$(cat << EOF
{
  "person": {
    "names": [{"givenName": "${PATIENT_GIVEN}", "familyName": "${PATIENT_FAMILY}"}],
    "gender": "${PATIENT_GENDER}",
    "birthdate": "${PATIENT_DOB}",
    "addresses": [{"address1": "District Hospital Area", "cityVillage": "Nairobi", "country": "Kenya"}]
  },
  "identifiers": [{
    "identifier": "${PATIENT_IDENTIFIER}",
    "identifierType": "${ID_TYPE_UUID}",
    "location": "Unknown Location",
    "preferred": true
  }]
}
EOF
)
    CREATE_RESP=$(openmrs_api_post "/patient" "$PATIENT_PAYLOAD" 2>/dev/null)
    PATIENT_UUID=$(echo "$CREATE_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('uuid',''))" 2>/dev/null)

    if [ -z "$PATIENT_UUID" ]; then
        echo "[ERROR] Failed to create patient ${PATIENT_IDENTIFIER}"
        echo "Response: $CREATE_RESP"
        exit 1
    fi
    echo "[SETUP] Created patient ${PATIENT_IDENTIFIER} with UUID: ${PATIENT_UUID}"
else
    PATIENT_UUID=$(echo "$EXISTING" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][0]['uuid'])" 2>/dev/null)
    echo "[SETUP] Patient ${PATIENT_IDENTIFIER} already exists with UUID: ${PATIENT_UUID}"
fi

# Verify patient UUID is valid
if [ -z "$PATIENT_UUID" ]; then
    echo "[ERROR] Could not obtain patient UUID"
    exit 1
fi

# Save patient UUID for export script
echo "$PATIENT_UUID" > /tmp/cdfu_patient_uuid
echo "$PATIENT_IDENTIFIER" > /tmp/cdfu_patient_identifier

# Record baseline - count current encounters for this patient
BASELINE_ENCOUNTERS=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=default" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")
echo "$BASELINE_ENCOUNTERS" > /tmp/cdfu_initial_encounter_count
echo "[SETUP] Baseline encounter count: ${BASELINE_ENCOUNTERS}"

# Record baseline - count current drug orders
BASELINE_ORDERS=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&v=default" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")
echo "$BASELINE_ORDERS" > /tmp/cdfu_initial_order_count
echo "[SETUP] Baseline drug order count: ${BASELINE_ORDERS}"

# Record baseline - count current observations
BASELINE_OBS=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=default" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")
echo "$BASELINE_OBS" > /tmp/cdfu_initial_obs_count
echo "[SETUP] Baseline obs count: ${BASELINE_OBS}"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/cdfu_start_time

# Open browser to Bahmni clinical module for this patient
PATIENT_URL="${BAHMNI_BASE_URL}/bahmni/clinical#/default/patient/${PATIENT_UUID}/dashboard"
if ! restart_firefox "${BAHMNI_LOGIN_URL}" 5; then
    echo "[WARN] Browser launch had issues, continuing..."
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png
echo "[SETUP] Initial screenshot saved"

echo "[SETUP] Patient UUID: ${PATIENT_UUID}"
echo "[SETUP] Patient Identifier: ${PATIENT_IDENTIFIER}"
echo "[SETUP] Baseline encounters: ${BASELINE_ENCOUNTERS}"
echo "=== Setup Complete ==="
