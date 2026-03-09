#!/bin/bash
# Setup: metabolic_syndrome_complication task
# Patient: Yolando Flatley (DOB: 1960-02-10)

echo "=== Setting up metabolic_syndrome_complication task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/metabolic_syndrome_complication_start_ts

echo "Locating Yolando Flatley..."
PATIENT_UUID=$(get_patient_uuid "Yolando Flatley")
if [ -z "$PATIENT_UUID" ]; then
    echo "Patient not found, attempting seed..."
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Yolando Flatley")
fi
if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Cannot find Yolando Flatley after seeding."
    exit 1
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/metabolic_syndrome_complication_patient_uuid

# Remove any pre-existing obesity conditions
echo "Removing any existing obesity conditions..."
EXISTING_OBESITY=$(omrs_get "/condition?patient=$PATIENT_UUID&v=default" | \
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
    if 'obes' in name or 'overweight' in name:
        print(c['uuid'])
" 2>/dev/null || true)
while IFS= read -r c_uuid; do
    [ -n "$c_uuid" ] && omrs_delete "/condition/$c_uuid" > /dev/null || true
done <<< "$EXISTING_OBESITY"

INITIAL_COND_COUNT=$(omrs_get "/condition?patient=$PATIENT_UUID&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); print(len(r.get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_COND_COUNT" > /tmp/metabolic_syndrome_complication_initial_condition_count

INITIAL_APPT_COUNT=$(omrs_get "/appointment?patientUuid=$PATIENT_UUID&v=default" | \
    python3 -c "import sys, json; r = json.load(sys.stdin); data = r.get('results', r) if isinstance(r, dict) else r; print(len(data) if isinstance(data, list) else 0)" 2>/dev/null || echo "0")
echo "$INITIAL_APPT_COUNT" > /tmp/metabolic_syndrome_complication_initial_appt_count

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
take_screenshot /tmp/metabolic_syndrome_complication_start_screenshot.png

echo ""
echo "=== metabolic_syndrome_complication setup complete ==="
echo ""
echo "TASK: Yolando Flatley (DOB: 1960-02-10) — Metabolic Syndrome Complication"
echo "  1. Record vitals: BP 158/96 mmHg, Weight 102 kg, Pulse 78, Temp 37.0 C"
echo "  2. Add condition: Obesity (Confirmed)"
echo "  3. Schedule follow-up appointment within 21 days"
echo ""
echo "Login: admin / Admin123"
