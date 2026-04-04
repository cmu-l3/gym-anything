#!/bin/bash
# Setup: record_vitals task
# Creates an active visit for Larissa Kuhic, opens the patient chart.

echo "=== Setting up record_vitals task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Find Larissa Kuhic
echo "Locating Larissa Kuhic..."
PATIENT_UUID=$(get_patient_uuid "Larissa Kuhic")
if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Larissa Kuhic not found. Running seed script..."
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Larissa Kuhic")
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Cannot find Larissa Kuhic after seeding."
    exit 1
fi

# Delete all prior vitals encounters so the vitals panel starts empty.
# This prevents agents from seeing pre-existing Synthea baseline values and
# mistakenly concluding the task is already done.
echo "Clearing existing vitals encounters for Larissa Kuhic..."
VITALS_ENC_TYPE="67a71486-1a54-468f-ac3e-7091a9a79584"
EXISTING_ENCS=$(omrs_get "/encounter?patient=$PATIENT_UUID&encounterType=$VITALS_ENC_TYPE&limit=100&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(e['uuid']) for e in r.get('results',[])]" 2>/dev/null || true)
while IFS= read -r enc_uuid; do
    if [ -n "$enc_uuid" ]; then
        omrs_delete "/encounter/$enc_uuid" > /dev/null || true
    fi
done <<< "$EXISTING_ENCS"

# End any existing open visits first
echo "Closing any existing open visits..."
OPEN_VISITS=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(v['uuid']) for v in r.get('results',[]) if not v.get('stopDatetime')]" 2>/dev/null || true)
while IFS= read -r v_uuid; do
    if [ -n "$v_uuid" ]; then
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
        omrs_post "/visit/$v_uuid" "{\"stopDatetime\":\"$NOW\"}" > /dev/null || true
    fi
done <<< "$OPEN_VISITS"

# Get visit type and location UUIDs
VISIT_TYPE=$(omrs_get "/visittype?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); vts=r.get('results',[]); print(next((v['uuid'] for v in vts if 'facility' in v.get('display','').lower()), vts[0]['uuid'] if vts else ''))" 2>/dev/null || echo "")
LOCATION=$(omrs_get "/location?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); locs=r.get('results',[]); print(next((l['uuid'] for l in locs if 'outpatient' in l.get('display','').lower()), locs[0]['uuid'] if locs else ''))" 2>/dev/null || echo "")

# Start a fresh active visit for this patient
echo "Creating active visit..."
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
VISIT_PAYLOAD="{\"patient\":\"$PATIENT_UUID\",\"visitType\":\"$VISIT_TYPE\",\"startDatetime\":\"$NOW\",\"location\":\"$LOCATION\"}"
VISIT_UUID=$(omrs_post "/visit" "$VISIT_PAYLOAD" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || echo "")
echo "Active visit UUID: $VISIT_UUID"
echo "$VISIT_UUID" > /tmp/task_visit_uuid

# Open Firefox on this patient's chart
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== record_vitals task setup complete ==="
echo ""
echo "TASK: Record vitals for Larissa Kuhic"
echo "  Weight: 76.5 kg | Height: 163 cm | Temp: 37.1°C"
echo "  Pulse: 68 | BP: 119/81 | SpO2: 98%"
echo ""
echo "Login: admin / Admin123"
