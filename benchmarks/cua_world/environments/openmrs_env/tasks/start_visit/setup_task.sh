#!/bin/bash
# Setup: start_visit task
# Ensures Shalanda Parker has NO open visits, opens her patient chart.

echo "=== Setting up start_visit task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Find Shalanda Parker
echo "Locating Shalanda Parker..."
PATIENT_UUID=$(get_patient_uuid "Shalanda Parker")
if [ -z "$PATIENT_UUID" ]; then
    echo "Running seed script..."
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Shalanda Parker")
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid

# Close all open visits so agent must start a new one
echo "Closing any existing open visits for Shalanda Parker..."
OPEN_VISITS=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(v['uuid']) for v in r.get('results',[]) if not v.get('stopDatetime')]" 2>/dev/null || true)
while IFS= read -r v_uuid; do
    if [ -n "$v_uuid" ]; then
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
        omrs_post "/visit/$v_uuid" "{\"stopDatetime\":\"$NOW\"}" > /dev/null || true
        echo "  Closed visit $v_uuid"
    fi
done <<< "$OPEN_VISITS"

# Record visit count before task
VISIT_COUNT=$(omrs_get "/visit?patient=$PATIENT_UUID&v=count&limit=1" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('totalCount',0))" 2>/dev/null || echo "0")
echo "$VISIT_COUNT" > /tmp/initial_visit_count

# Open Firefox on the patient chart
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== start_visit task setup complete ==="
echo ""
echo "TASK: Start a new Facility Visit for Shalanda Parker"
echo "  Location: Outpatient Clinic"
echo ""
echo "Login: admin / Admin123"
