#!/bin/bash
# Setup: record_medication task
# Opens Eliseo Nader's chart at Medications panel.

echo "=== Setting up record_medication task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Find Eliseo Nader
echo "Locating Eliseo Nader..."
PATIENT_UUID=$(get_patient_uuid "Eliseo Nader")
if [ -z "$PATIENT_UUID" ]; then
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Eliseo Nader")
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid

# Remove any existing Aspirin medication records to allow re-runs
echo "Cleaning existing Aspirin drug orders..."
EXISTING_ORDERS=$(omrs_get "/order?patient=$PATIENT_UUID&v=default&limit=100" | \
    python3 -c "
import sys,json
r=json.load(sys.stdin)
for o in r.get('results',[]):
    drug = (o.get('drug') or o.get('concept') or {}).get('display','')
    if 'aspirin' in drug.lower():
        print(o['uuid'])
" 2>/dev/null || true)
while IFS= read -r o_uuid; do
    [ -n "$o_uuid" ] && omrs_delete "/order/$o_uuid" > /dev/null || true
done <<< "$EXISTING_ORDERS"

# Record initial active medication count
INITIAL_COUNT=$(omrs_get "/order?patient=$PATIENT_UUID&v=default&limit=100" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_medication_count

# Create an active visit so the agent can record medication within a visit context
echo "Closing any existing open visits..."
OPEN_VISITS=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(v['uuid']) for v in r.get('results',[]) if not v.get('stopDatetime')]" 2>/dev/null || true)
while IFS= read -r v_uuid; do
    if [ -n "$v_uuid" ]; then
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
        omrs_post "/visit/$v_uuid" "{\"stopDatetime\":\"$NOW\"}" > /dev/null || true
    fi
done <<< "$OPEN_VISITS"

VISIT_TYPE=$(omrs_get "/visittype?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); vts=r.get('results',[]); print(next((v['uuid'] for v in vts if 'facility' in v.get('display','').lower()), vts[0]['uuid'] if vts else ''))" 2>/dev/null || echo "")
LOCATION=$(omrs_get "/location?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); locs=r.get('results',[]); print(next((l['uuid'] for l in locs if 'outpatient' in l.get('display','').lower()), locs[0]['uuid'] if locs else ''))" 2>/dev/null || echo "")

echo "Creating active visit for Eliseo Nader..."
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
VISIT_UUID=$(omrs_post "/visit" "{\"patient\":\"$PATIENT_UUID\",\"visitType\":\"$VISIT_TYPE\",\"startDatetime\":\"$NOW\",\"location\":\"$LOCATION\"}" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('uuid',''))" 2>/dev/null || echo "")
echo "Active visit UUID: $VISIT_UUID"
echo "$VISIT_UUID" > /tmp/task_visit_uuid

# Open Firefox on patient Medications chart panel
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Medications"
ensure_openmrs_logged_in "$PATIENT_URL"
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== record_medication task setup complete ==="
echo ""
echo "TASK: Add active medication for Eliseo Nader"
echo "  Drug:      Aspirin"
echo "  Dose:      81 mg"
echo "  Frequency: Once daily"
echo "  Route:     Oral"
echo ""
echo "Login: admin / Admin123"
