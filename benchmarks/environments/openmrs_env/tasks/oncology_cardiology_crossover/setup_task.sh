#!/bin/bash
# Setup: oncology_cardiology_crossover task
# Patient: Mateo Matias (DOB: 1946-07-19)

echo "=== Setting up oncology_cardiology_crossover task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/oncology_cardiology_crossover_start_ts

echo "Locating Mateo Matias..."
PATIENT_UUID=$(get_patient_uuid "Mateo Matias")
if [ -z "$PATIENT_UUID" ]; then
    echo "Patient not found, attempting seed..."
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Mateo Matias")
fi
if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Cannot find Mateo Matias after seeding."
    exit 1
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/oncology_cardiology_crossover_patient_uuid

# Remove any pre-existing contrast allergy
echo "Removing any existing contrast media allergy..."
EXISTING_CONTRAST=$(omrs_get "/allergy?patient=$PATIENT_UUID&v=default" | \
    python3 -c "
import sys, json
r = json.load(sys.stdin)
for a in r.get('results', []):
    allergen = a.get('allergen', {})
    coded = (allergen.get('codedAllergen', {}) or {}).get('display', '').lower()
    noncoded = (allergen.get('nonCodedAllergen', '') or '').lower()
    name = coded + ' ' + noncoded
    if 'contrast' in name or 'iodine' in name or 'iodinated' in name:
        print(a['uuid'])
" 2>/dev/null || true)
while IFS= read -r a_uuid; do
    [ -n "$a_uuid" ] && omrs_delete "/allergy/$a_uuid" > /dev/null || true
done <<< "$EXISTING_CONTRAST"

INITIAL_APPT_COUNT=$(omrs_get "/appointment?patientUuid=$PATIENT_UUID&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); data = r.get('results', r) if isinstance(r, dict) else r; print(len(data) if isinstance(data, list) else 0)" 2>/dev/null || echo "0")
echo "$INITIAL_APPT_COUNT" > /tmp/oncology_cardiology_crossover_initial_appt_count

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
take_screenshot /tmp/oncology_cardiology_crossover_start_screenshot.png

echo ""
echo "=== oncology_cardiology_crossover setup complete ==="
echo ""
echo "TASK: Mateo Matias (DOB: 1946-07-19) — Oncology-Cardiology Crossover"
echo "  1. Add allergy: Iodinated contrast media → Urticaria → Moderate"
echo "  2. Record vitals: BP 128/78 mmHg, Weight 72 kg, Pulse 66, Temp 37.2 C"
echo "  3. Schedule follow-up appointment within 28 days"
echo ""
echo "Login: admin / Admin123"
