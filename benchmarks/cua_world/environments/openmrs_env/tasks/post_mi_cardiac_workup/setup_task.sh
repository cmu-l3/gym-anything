#!/bin/bash
# Setup: post_mi_cardiac_workup task
# Patient: Jesse Becker (DOB: 1943-02-04)

echo "=== Setting up post_mi_cardiac_workup task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/post_mi_cardiac_workup_start_ts

echo "Locating Jesse Becker..."
PATIENT_UUID=$(get_patient_uuid "Jesse Becker")
if [ -z "$PATIENT_UUID" ]; then
    echo "Patient not found, attempting seed..."
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Jesse Becker")
fi
if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Cannot find Jesse Becker after seeding."
    exit 1
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/post_mi_cardiac_workup_patient_uuid

# Remove any pre-existing Codeine allergy
echo "Removing any existing Codeine allergy..."
EXISTING_CODEINE=$(omrs_get "/allergy?patient=$PATIENT_UUID&v=default" | \
    python3 -c "
import sys, json
r = json.load(sys.stdin)
for a in r.get('results', []):
    allergen = a.get('allergen', {})
    coded = (allergen.get('codedAllergen', {}) or {}).get('display', '').lower()
    noncoded = (allergen.get('nonCodedAllergen', '') or '').lower()
    name = coded + ' ' + noncoded
    if 'codeine' in name:
        print(a['uuid'])
" 2>/dev/null || true)
while IFS= read -r a_uuid; do
    [ -n "$a_uuid" ] && omrs_delete "/allergy/$a_uuid" > /dev/null || true
done <<< "$EXISTING_CODEINE"

INITIAL_ALLERGY_COUNT=$(omrs_get "/allergy?patient=$PATIENT_UUID&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(len(r.get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_ALLERGY_COUNT" > /tmp/post_mi_cardiac_workup_initial_allergy_count

# Remove any pre-existing diabetes conditions
echo "Removing any existing diabetes conditions..."
EXISTING_DM=$(omrs_get "/condition?patient=$PATIENT_UUID&v=default" | \
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
    if 'diabet' in name or 'dm2' in name or 'type 2' in name:
        print(c['uuid'])
" 2>/dev/null || true)
while IFS= read -r c_uuid; do
    [ -n "$c_uuid" ] && omrs_delete "/condition/$c_uuid" > /dev/null || true
done <<< "$EXISTING_DM"

INITIAL_COND_COUNT=$(omrs_get "/condition?patient=$PATIENT_UUID&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(len(r.get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_COND_COUNT" > /tmp/post_mi_cardiac_workup_initial_condition_count

# Record initial lab order count
INITIAL_ORDER_COUNT=$(omrs_get "/order?patient=$PATIENT_UUID&v=default&limit=100" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(len(r.get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/post_mi_cardiac_workup_initial_order_count

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

PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"
sleep 2
take_screenshot /tmp/post_mi_cardiac_workup_start_screenshot.png

echo ""
echo "=== post_mi_cardiac_workup setup complete ==="
echo ""
echo "TASK: Jesse Becker (DOB: 1943-02-04) — Post-MI Cardiac Workup"
echo "  1. Add allergy: Codeine → Nausea and vomiting → Moderate"
echo "  2. Add condition: Type 2 diabetes mellitus (Confirmed)"
echo "  3. Order lab test: Creatinine (serum)"
echo ""
echo "Login: admin / Admin123"
