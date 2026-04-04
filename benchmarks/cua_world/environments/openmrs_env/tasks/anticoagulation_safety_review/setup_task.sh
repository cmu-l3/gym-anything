#!/bin/bash
# Setup: anticoagulation_safety_review task
# Patient: Rosario Ortiz (DOB: 1944-06-15)
# Clears existing aspirin allergies and CKD conditions, records baselines, creates an active visit.

echo "=== Setting up anticoagulation_safety_review task ==="
source /workspace/scripts/task_utils.sh

# Record task start timestamp FIRST
date +%s > /tmp/anticoagulation_safety_review_start_ts

# Locate Rosario Ortiz
echo "Locating Rosario Ortiz..."
PATIENT_UUID=$(get_patient_uuid "Rosario Ortiz")
if [ -z "$PATIENT_UUID" ]; then
    echo "Patient not found, attempting seed..."
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Rosario Ortiz")
fi
if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Cannot find Rosario Ortiz after seeding."
    exit 1
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/anticoagulation_safety_review_patient_uuid

# Remove any pre-existing Aspirin allergy to ensure clean state
echo "Removing any existing Aspirin allergy..."
EXISTING_ASPIRIN=$(omrs_get "/allergy?patient=$PATIENT_UUID&v=default" | \
    python3 -c "
import sys, json
r = json.load(sys.stdin)
for a in r.get('results', []):
    allergen = a.get('allergen', {})
    coded = (allergen.get('codedAllergen', {}) or {}).get('display', '').lower()
    noncoded = (allergen.get('nonCodedAllergen', '') or '').lower()
    name = coded + ' ' + noncoded
    if 'aspirin' in name or 'acetylsalicylic' in name:
        print(a['uuid'])
" 2>/dev/null || true)
while IFS= read -r a_uuid; do
    [ -n "$a_uuid" ] && omrs_delete "/allergy/$a_uuid" > /dev/null || true
done <<< "$EXISTING_ASPIRIN"

# Record initial allergy count (baseline)
INITIAL_ALLERGY_COUNT=$(omrs_get "/allergy?patient=$PATIENT_UUID&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(len(r.get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_ALLERGY_COUNT" > /tmp/anticoagulation_safety_review_initial_allergy_count

# Remove any pre-existing CKD conditions to ensure clean state
echo "Removing any existing CKD conditions..."
EXISTING_CKD=$(omrs_get "/condition?patient=$PATIENT_UUID&v=default" | \
    python3 -c "
import sys, json
r = json.load(sys.stdin)
for c in r.get('results', []):
    name = ''
    cond = c.get('condition', {})
    if isinstance(cond, dict):
        name = cond.get('display', '').lower()
    noncoded = str(c.get('conditionNonCoded', '') or '').lower()
    name = name + ' ' + noncoded
    if 'kidney' in name or 'renal' in name or 'ckd' in name:
        print(c['uuid'])
" 2>/dev/null || true)
while IFS= read -r c_uuid; do
    [ -n "$c_uuid" ] && omrs_delete "/condition/$c_uuid" > /dev/null || true
done <<< "$EXISTING_CKD"

# Record initial condition count
INITIAL_COND_COUNT=$(omrs_get "/condition?patient=$PATIENT_UUID&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(len(r.get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_COND_COUNT" > /tmp/anticoagulation_safety_review_initial_condition_count

# Close any existing open visits (vitals require an active visit)
echo "Closing any existing open visits..."
OPEN_VISITS=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); [print(v['uuid']) for v in r.get('results', []) if not v.get('stopDatetime')]" 2>/dev/null || true)
while IFS= read -r v_uuid; do
    if [ -n "$v_uuid" ]; then
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
        omrs_post "/visit/$v_uuid" "{\"stopDatetime\":\"$NOW\"}" > /dev/null || true
    fi
done <<< "$OPEN_VISITS"

# Create a fresh active visit
echo "Creating active visit..."
VISIT_TYPE=$(omrs_get "/visittype?v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); vts = r.get('results', []); print(next((v['uuid'] for v in vts if 'facility' in v.get('display', '').lower()), vts[0]['uuid'] if vts else ''))" 2>/dev/null || echo "")
LOCATION=$(omrs_get "/location?v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); locs = r.get('results', []); print(next((l['uuid'] for l in locs if 'outpatient' in l.get('display', '').lower()), locs[0]['uuid'] if locs else ''))" 2>/dev/null || echo "")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
VISIT_PAYLOAD="{\"patient\":\"$PATIENT_UUID\",\"visitType\":\"$VISIT_TYPE\",\"startDatetime\":\"$NOW\",\"location\":\"$LOCATION\"}"
VISIT_UUID=$(omrs_post "/visit" "$VISIT_PAYLOAD" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(r.get('uuid', ''))" 2>/dev/null || echo "")
echo "Active visit UUID: $VISIT_UUID"

# Clear any existing vitals encounters so the panel starts empty
echo "Clearing existing vitals encounters..."
VITALS_ENC_TYPE="67a71486-1a54-468f-ac3e-7091a9a79584"
EXISTING_ENCS=$(omrs_get "/encounter?patient=$PATIENT_UUID&encounterType=$VITALS_ENC_TYPE&limit=100&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); [print(e['uuid']) for e in r.get('results', [])]" 2>/dev/null || true)
while IFS= read -r enc_uuid; do
    [ -n "$enc_uuid" ] && omrs_delete "/encounter/$enc_uuid" > /dev/null || true
done <<< "$EXISTING_ENCS"

# Open Firefox on patient chart
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"
sleep 2
take_screenshot /tmp/anticoagulation_safety_review_start_screenshot.png

echo ""
echo "=== anticoagulation_safety_review setup complete ==="
echo ""
echo "TASK: Rosario Ortiz (DOB: 1944-06-15) — Anticoagulation Safety Review"
echo "  1. Add allergy: Aspirin → Anaphylaxis → Severe"
echo "  2. Record vitals: BP 148/90 mmHg, Weight 87 kg, Pulse 92, Temp 37.4°C"
echo "  3. Add condition: Chronic kidney disease (Confirmed)"
echo ""
echo "Login: admin / Admin123"
