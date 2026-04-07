#!/bin/bash
# Setup: search_update_patient task
# Ensures Maria Garcia exists with old contact info, then opens Firefox on Care2x.

echo "=== Setting up search_update_patient task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Verify that Maria Garcia exists in the database
echo "Checking for patient Maria Garcia..."
PATIENT_PID=$(get_patient_pid "Maria" "Garcia")
if [ -z "$PATIENT_PID" ]; then
    echo "ERROR: Patient Maria Garcia not found in database!"
    exit 1
fi
echo "Patient PID: $PATIENT_PID"

# Reset the patient's contact info to OLD values (to allow re-runs)
echo "Resetting contact info to old values..."
care2x_query "UPDATE care_person SET phone_1_nr='713-555-0198', email='maria.garcia@mail.com' WHERE pid='$PATIENT_PID';" || true

# Record old contact info for verification
OLD_PHONE=$(care2x_query_single "SELECT phone_1_nr FROM care_person WHERE pid='$PATIENT_PID';")
OLD_EMAIL=$(care2x_query_single "SELECT email FROM care_person WHERE pid='$PATIENT_PID';")
echo "Old phone: $OLD_PHONE"
echo "Old email: $OLD_EMAIL"

# Open Firefox on Care2x
ensure_firefox_on_url "$CARE2X_URL"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== search_update_patient task setup complete ==="
echo ""
echo "TASK: Search for patient Maria Garcia and update contact info"
echo "  Patient:    Maria Garcia (PID: $PATIENT_PID)"
echo "  New phone:  713-555-0299"
echo "  New email:  maria.garcia@newmail.com"
echo ""
echo "Login: admin / care2x_admin"
