#!/bin/bash
# Setup: add_diagnosis task
# Creates an active visit for Ezekiel Walter, opens his chart.

echo "=== Setting up add_diagnosis task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Find Ezekiel Walter
echo "Locating Ezekiel Walter..."
PATIENT_UUID=$(get_patient_uuid "Ezekiel Walter")
if [ -z "$PATIENT_UUID" ]; then
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Ezekiel Walter")
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid

# Get visit type and location
VISIT_TYPE=$(omrs_get "/visittype?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); vts=r.get('results',[]); print(next((v['uuid'] for v in vts if 'facility' in v.get('display','').lower()), vts[0]['uuid'] if vts else ''))" 2>/dev/null || echo "")
LOCATION=$(omrs_get "/location?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); locs=r.get('results',[]); print(next((l['uuid'] for l in locs if 'outpatient' in l.get('display','').lower()), locs[0]['uuid'] if locs else ''))" 2>/dev/null || echo "")

# Close any open visits
OPEN_VISITS=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(v['uuid']) for v in r.get('results',[]) if not v.get('stopDatetime')]" 2>/dev/null || true)
while IFS= read -r v_uuid; do
    if [ -n "$v_uuid" ]; then
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
        omrs_post "/visit/$v_uuid" "{\"stopDatetime\":\"$NOW\"}" > /dev/null || true
    fi
done <<< "$OPEN_VISITS"

# Create fresh active visit
echo "Creating active visit..."
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
VISIT_PAYLOAD="{\"patient\":\"$PATIENT_UUID\",\"visitType\":\"$VISIT_TYPE\",\"startDatetime\":\"$NOW\",\"location\":\"$LOCATION\"}"
VISIT_UUID=$(omrs_post "/visit" "$VISIT_PAYLOAD" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || echo "")
echo "Active visit UUID: $VISIT_UUID"
echo "$VISIT_UUID" > /tmp/task_visit_uuid

# Open Firefox on patient chart
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== add_diagnosis task setup complete ==="
echo ""
echo "TASK: Add Hypertension diagnosis for Ezekiel Walter"
echo "  Diagnosis: Hypertension"
echo "  Certainty: Confirmed"
echo "  Primary/Secondary: Primary"
echo ""
echo "Login: admin / Admin123"
