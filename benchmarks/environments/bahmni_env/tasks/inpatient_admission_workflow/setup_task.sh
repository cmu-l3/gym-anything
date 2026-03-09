#!/bin/bash
# Setup script for Inpatient Admission Workflow Task
echo "=== Setting up Inpatient Admission Workflow Task ==="

source /workspace/scripts/task_utils.sh

PATIENT_IDENTIFIER="BAH000023"
PATIENT_GIVEN="Valentina"
PATIENT_FAMILY="Torres"
PATIENT_DOB="1985-07-22"
PATIENT_GENDER="F"

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
results = d.get('results', [])
if results:
    print(results[0]['uuid'])
" 2>/dev/null)

    PATIENT_PAYLOAD=$(cat << EOF
{
  "person": {
    "names": [{"givenName": "${PATIENT_GIVEN}", "familyName": "${PATIENT_FAMILY}"}],
    "gender": "${PATIENT_GENDER}",
    "birthdate": "${PATIENT_DOB}",
    "addresses": [{"address1": "Nairobi Central", "cityVillage": "Nairobi", "country": "Kenya"}]
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

if [ -z "$PATIENT_UUID" ]; then
    echo "[ERROR] Could not obtain patient UUID"
    exit 1
fi

echo "$PATIENT_UUID" > /tmp/iaw_patient_uuid
echo "$PATIENT_IDENTIFIER" > /tmp/iaw_patient_identifier

# Record baseline state
BASELINE_ENCOUNTERS=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=default" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")
echo "$BASELINE_ENCOUNTERS" > /tmp/iaw_initial_encounter_count

BASELINE_ORDERS=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&v=default" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")
echo "$BASELINE_ORDERS" > /tmp/iaw_initial_order_count

BASELINE_OBS=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=default" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")
echo "$BASELINE_OBS" > /tmp/iaw_initial_obs_count

echo "[SETUP] Baseline - encounters: ${BASELINE_ENCOUNTERS}, orders: ${BASELINE_ORDERS}, obs: ${BASELINE_OBS}"

# Record timestamp
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/iaw_start_time

# Launch browser
if ! restart_firefox "${BAHMNI_LOGIN_URL}" 5; then
    echo "[WARN] Browser launch had issues, continuing..."
fi

take_screenshot /tmp/task_start.png

echo "[SETUP] Patient UUID: ${PATIENT_UUID}"
echo "[SETUP] Identifier: ${PATIENT_IDENTIFIER}"
echo "=== Setup Complete ==="
