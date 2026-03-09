#!/bin/bash
# Setup: add_appointment task
# Opens Firefox on the Appointments module for Jona Botsford.

echo "=== Setting up add_appointment task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Find Jona Botsford
echo "Locating Jona Botsford..."
PATIENT_UUID=$(get_patient_uuid "Jona Botsford")
if [ -z "$PATIENT_UUID" ]; then
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Jona Botsford")
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid

# Record initial appointment count for this patient
INITIAL_COUNT=$(omrs_get "/appointment?patientUuid=$PATIENT_UUID&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])) if isinstance(r,dict) else len(r) if isinstance(r,list) else 0)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_appointment_count
echo "Initial appointment count: $INITIAL_COUNT"

# Today and 30-day window
TODAY=$(date +%Y-%m-%d)
MAX_DATE=$(date -d "+30 days" +%Y-%m-%d)
echo "$TODAY" > /tmp/valid_date_start
echo "$MAX_DATE" > /tmp/valid_date_end

# Open Firefox on Jona Botsford's patient chart so the patient is clearly visible
# as the task subject. The agent will navigate from the chart to the Appointments module.
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== add_appointment task setup complete ==="
echo ""
echo "TASK: Schedule an appointment for Jona Botsford"
echo "  Service:  General Medicine"
echo "  Date:     Any date within next 30 days ($TODAY to $MAX_DATE)"
echo "  Duration: 30 minutes"
echo "  Type:     Scheduled"
echo ""
echo "Login: admin / Admin123"
