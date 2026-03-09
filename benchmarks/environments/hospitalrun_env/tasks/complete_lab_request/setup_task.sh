#!/bin/bash
set -e
echo "=== Setting up complete_lab_request task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is ready
echo "Checking HospitalRun availability..."
wait_for_db_ready

# 2. Ensure Patient Maria Santos exists (patient_p1_00001)
echo "Ensuring patient Maria Santos exists..."
PATIENT_ID="patient_p1_00001"
PATIENT_DOC=$(cat <<EOF
{
  "type": "patient",
  "data": {
    "firstName": "Maria",
    "lastName": "Santos",
    "sex": "Female",
    "dateOfBirth": "1990-05-15",
    "address": "123 Task Lane",
    "phone": "555-0199",
    "email": "maria.santos@example.com",
    "patientType": "Outpatient"
  }
}
EOF
)

# Check if exists, if not create/update
CURRENT_PATIENT=$(hr_couch_get "$PATIENT_ID")
if echo "$CURRENT_PATIENT" | grep -q "error"; then
    hr_couch_put "$PATIENT_ID" "$PATIENT_DOC"
    echo "Created patient $PATIENT_ID"
else
    echo "Patient $PATIENT_ID already exists"
fi

# 3. Create the specific Lab Request document
# We use a fixed ID "lab_p1_task_cbc" to make verification reliable
LAB_ID="lab_p1_task_cbc"
echo "Resetting Lab Request $LAB_ID..."

# Delete if exists to ensure clean state
hr_couch_delete "$LAB_ID"

# Create new lab request with status "Requested" and empty results
LAB_DOC=$(cat <<EOF
{
  "type": "lab",
  "data": {
    "patient": "$PATIENT_ID",
    "labType": "CBC - Complete Blood Count",
    "requestDate": "$(date +%s%3N)",
    "status": "requested",
    "notes": "",
    "result": "",
    "requestedBy": "Dr. Task Setup"
  }
}
EOF
)

hr_couch_put "$LAB_ID" "$LAB_DOC"
echo "Created lab request $LAB_ID with status 'requested'"

# 4. Record initial revision for anti-gaming
INITIAL_DOC=$(hr_couch_get "$LAB_ID")
INITIAL_REV=$(echo "$INITIAL_DOC" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$INITIAL_REV" > /tmp/initial_lab_rev.txt
echo "Recorded initial revision: $INITIAL_REV"

# 5. Prepare Browser
echo "Launching Firefox..."
ensure_hospitalrun_logged_in

# Navigate specifically to the Labs section to save the agent some time
# (Optional, but helps ensures the list is loaded)
navigate_firefox_to "http://localhost:3000/#/labs"

# 6. Capture initial state
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Setup complete ==="