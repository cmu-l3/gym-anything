#!/bin/bash
echo "=== Setting up mark_patient_deceased task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    if curl -s http://localhost:3000/ >/dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Fix PouchDB sync issues (critical for this env)
fix_offline_sync

# 3. Seed Patient "Eleanor Rigby"
# We force a specific ID so we can easily retrieve it later
PATIENT_ID="patient_p1_eleanor"
echo "Seeding patient Eleanor Rigby ($PATIENT_ID)..."

# Construct the patient document
# Note: HospitalRun usually wraps fields in a 'data' object for PouchDB/CouchDB sync
PATIENT_DOC=$(cat <<EOF
{
  "_id": "$PATIENT_ID",
  "data": {
    "friendlyId": "P_ELEANOR",
    "firstName": "Eleanor",
    "lastName": "Rigby",
    "sex": "Female",
    "dateOfBirth": "1945-06-15T00:00:00.000Z",
    "address": "Church Lane, Liverpool",
    "phone": "555-0199",
    "email": "eleanor@example.com",
    "deceased": false,
    "patientType": "Patient",
    "status": "Active"
  },
  "type": "patient"
}
EOF
)

# Delete if exists to ensure clean state (alive)
hr_couch_delete "$PATIENT_ID" || true
sleep 1

# Put new doc
hr_couch_put "$PATIENT_ID" "$PATIENT_DOC"

# 4. Launch Firefox and login
ensure_hospitalrun_logged_in

# 5. Wait for DB sync in browser
wait_for_db_ready

# 6. Navigate to Patients list to start
navigate_firefox_to "http://localhost:3000/#/patients"

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="