#!/bin/bash
# Setup: order_lab_test task
# Creates an active visit for Paul Tremblay, opens his chart.

echo "=== Setting up order_lab_test task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Find Paul Tremblay
echo "Locating Paul Tremblay..."
PATIENT_UUID=$(get_patient_uuid "Paul Tremblay")
if [ -z "$PATIENT_UUID" ]; then
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Paul Tremblay")
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid

# Get visit type and location
VISIT_TYPE=$(omrs_get "/visittype?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); vts=r.get('results',[]); print(next((v['uuid'] for v in vts if 'facility' in v.get('display','').lower()), vts[0]['uuid'] if vts else ''))" 2>/dev/null || echo "")
LOCATION=$(omrs_get "/location?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); locs=r.get('results',[]); print(next((l['uuid'] for l in locs if 'outpatient' in l.get('display','').lower()), locs[0]['uuid'] if locs else ''))" 2>/dev/null || echo "")

# Close any existing open visits
OPEN_VISITS=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(v['uuid']) for v in r.get('results',[]) if not v.get('stopDatetime')]" 2>/dev/null || true)
while IFS= read -r v_uuid; do
    if [ -n "$v_uuid" ]; then
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
        omrs_post "/visit/$v_uuid" "{\"stopDatetime\":\"$NOW\"}" > /dev/null || true
    fi
done <<< "$OPEN_VISITS"

# Create fresh active visit
echo "Creating active visit for Paul Tremblay..."
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
VISIT_PAYLOAD="{\"patient\":\"$PATIENT_UUID\",\"visitType\":\"$VISIT_TYPE\",\"startDatetime\":\"$NOW\",\"location\":\"$LOCATION\"}"
VISIT_UUID=$(omrs_post "/visit" "$VISIT_PAYLOAD" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || echo "")
echo "Active visit UUID: $VISIT_UUID"
echo "$VISIT_UUID" > /tmp/task_visit_uuid

# Record initial order count
INITIAL_COUNT=$(omrs_get "/order?patient=$PATIENT_UUID&v=default&limit=100" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_order_count

# Open Firefox on patient chart - Orders tab
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== order_lab_test task setup complete ==="
echo ""
echo "TASK: Order a Complete Blood Count (CBC) lab test for Paul Tremblay"
echo "  Patient is in an active visit - navigate to the Orders or Tests panel"
echo ""
echo "Login: admin / Admin123"
