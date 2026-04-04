#!/bin/bash
# Setup: update_patient_info task
# Opens Angel Barrows's registration/demographics page.

echo "=== Setting up update_patient_info task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Find Angel Barrows
echo "Locating Angel Barrows..."
PATIENT_UUID=$(get_patient_uuid "Angel Barrows")
if [ -z "$PATIENT_UUID" ]; then
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Angel Barrows")
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid
PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")
echo "Person UUID: $PERSON_UUID"
echo "$PERSON_UUID" > /tmp/task_person_uuid

# Record current phone for verification
CURRENT_ATTRS=$(omrs_get "/person/$PERSON_UUID/attribute?v=default" 2>/dev/null || echo "{}")
echo "Current person attributes: $CURRENT_ATTRS"

# Open Firefox on patient registration (edit) page
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/edit"
ensure_openmrs_logged_in "$PATIENT_URL"
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== update_patient_info task setup complete ==="
echo ""
echo "TASK: Update phone number for Angel Barrows"
echo "  New phone: 617-555-0143"
echo ""
echo "Login: admin / Admin123"
