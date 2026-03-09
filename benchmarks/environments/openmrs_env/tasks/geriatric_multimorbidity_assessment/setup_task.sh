#!/bin/bash
# Setup: geriatric_multimorbidity_assessment task
# Patient: Corie Bergnaum (DOB: 1925-02-04)

echo "=== Setting up geriatric_multimorbidity_assessment task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/geriatric_multimorbidity_assessment_start_ts

echo "Locating Corie Bergnaum..."
PATIENT_UUID=$(get_patient_uuid "Corie Bergnaum")
if [ -z "$PATIENT_UUID" ]; then
    echo "Patient not found, attempting seed..."
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Corie Bergnaum")
fi
if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Cannot find Corie Bergnaum after seeding."
    exit 1
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/geriatric_multimorbidity_assessment_patient_uuid

# Remove any pre-existing Acetaminophen/Paracetamol medication orders
echo "Removing any existing Acetaminophen medication orders..."
EXISTING_ORDERS=$(omrs_get "/order?patient=$PATIENT_UUID&v=default&limit=100" | \
    python3 -c "
import sys, json
r = json.load(sys.stdin)
for o in r.get('results', []):
    drug = (o.get('drug', {}) or {})
    drug_name = (drug.get('display', '') or '').lower()
    concept_name = ((o.get('concept', {}) or {}).get('display', '') or '').lower()
    name = drug_name + ' ' + concept_name
    if 'acetaminophen' in name or 'paracetamol' in name or 'tylenol' in name:
        print(o['uuid'])
" 2>/dev/null || true)
while IFS= read -r o_uuid; do
    [ -n "$o_uuid" ] && omrs_delete "/order/$o_uuid" > /dev/null || true
done <<< "$EXISTING_ORDERS"

INITIAL_ORDER_COUNT=$(omrs_get "/order?patient=$PATIENT_UUID&v=default&limit=100" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(len(r.get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/geriatric_multimorbidity_assessment_initial_order_count

# Remove any pre-existing migraine conditions
echo "Removing any existing migraine conditions..."
EXISTING_MIGRAINE=$(omrs_get "/condition?patient=$PATIENT_UUID&v=default" | \
    python3 -c "
import sys, json
r = json.load(sys.stdin)
for c in r.get('results', []):
    name = ''
    cond = c.get('condition', {})
    if isinstance(cond, dict):
        name = (cond.get('display', '') or '').lower()
    noncoded = str(c.get('conditionNonCoded', '') or '').lower()
    name = name + ' ' + noncoded
    if 'migraine' in name or 'headache' in name:
        print(c['uuid'])
" 2>/dev/null || true)
while IFS= read -r c_uuid; do
    [ -n "$c_uuid" ] && omrs_delete "/condition/$c_uuid" > /dev/null || true
done <<< "$EXISTING_MIGRAINE"

INITIAL_COND_COUNT=$(omrs_get "/condition?patient=$PATIENT_UUID&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(len(r.get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_COND_COUNT" > /tmp/geriatric_multimorbidity_assessment_initial_condition_count

# Close any existing open visits
echo "Closing any existing open visits..."
OPEN_VISITS=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); [print(v['uuid']) for v in r.get('results', []) if not v.get('stopDatetime')]" 2>/dev/null || true)
while IFS= read -r v_uuid; do
    if [ -n "$v_uuid" ]; then
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
        omrs_post "/visit/$v_uuid" "{\"stopDatetime\":\"$NOW\"}" > /dev/null || true
    fi
done <<< "$OPEN_VISITS"

# Create active visit
echo "Creating active visit..."
VISIT_TYPE=$(omrs_get "/visittype?v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); vts = r.get('results', []); print(next((v['uuid'] for v in vts if 'facility' in v.get('display', '').lower()), vts[0]['uuid'] if vts else ''))" 2>/dev/null || echo "")
LOCATION=$(omrs_get "/location?v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); locs = r.get('results', []); print(next((l['uuid'] for l in locs if 'outpatient' in l.get('display', '').lower()), locs[0]['uuid'] if locs else ''))" 2>/dev/null || echo "")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
VISIT_UUID=$(omrs_post "/visit" "{\"patient\":\"$PATIENT_UUID\",\"visitType\":\"$VISIT_TYPE\",\"startDatetime\":\"$NOW\",\"location\":\"$LOCATION\"}" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(r.get('uuid', ''))" 2>/dev/null || echo "")
echo "Active visit UUID: $VISIT_UUID"

# Clear prior vitals encounters
echo "Clearing existing vitals encounters..."
VITALS_ENC_TYPE="67a71486-1a54-468f-ac3e-7091a9a79584"
EXISTING_ENCS=$(omrs_get "/encounter?patient=$PATIENT_UUID&encounterType=$VITALS_ENC_TYPE&limit=100&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); [print(e['uuid']) for e in r.get('results', [])]" 2>/dev/null || true)
while IFS= read -r enc_uuid; do
    [ -n "$enc_uuid" ] && omrs_delete "/encounter/$enc_uuid" > /dev/null || true
done <<< "$EXISTING_ENCS"

PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"
sleep 2
take_screenshot /tmp/geriatric_multimorbidity_assessment_start_screenshot.png

echo ""
echo "=== geriatric_multimorbidity_assessment setup complete ==="
echo ""
echo "TASK: Corie Bergnaum (DOB: 1925-02-04) — Geriatric Multimorbidity Assessment"
echo "  1. Record vitals: BP 162/88 mmHg, Weight 62 kg, Pulse 72, Temp 36.8°C"
echo "  2. Add condition: Migraine (Confirmed)"
echo "  3. Order medication: Acetaminophen 500mg tablet, oral, once daily"
echo ""
echo "Login: admin / Admin123"
