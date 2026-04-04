#!/bin/bash
set -e
echo "=== Setting up discharge_patient task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure HospitalRun is accessible
echo "Waiting for HospitalRun..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is up."
        break
    fi
    sleep 2
done

# 2. Fix PouchDB Sync issues (Standard Environment Fix)
# This is critical to prevent infinite loading spinners
fix_offline_sync

# 3. Seed Data: Patient Maria Santos
echo "Seeding patient Maria Santos..."
# ID: patient_p1_200001
PATIENT_DOC=$(cat <<EOF
{
  "data": {
    "friendlyId": "p1-200001",
    "firstName": "Maria",
    "lastName": "Santos",
    "sex": "Female",
    "dateOfBirth": "1980-05-15",
    "status": "Active",
    "address": "123 Samba Lane",
    "phone": "555-0199",
    "patientType": "Inpatient"
  }
}
EOF
)
# Delete existing if any to ensure clean state
hr_couch_delete "patient_p1_200001"
# Create new
hr_couch_put "patient_p1_200001" "$PATIENT_DOC"

# 4. Seed Data: Admitted Visit
echo "Seeding admitted visit..."
# ID: visit_p1_200001
VISIT_DOC=$(cat <<EOF
{
  "data": {
    "patient": "patient_p1_200001",
    "visitType": "Admission",
    "startDate": "2025-01-10T09:00:00.000Z",
    "endDate": "",
    "status": "Admitted",
    "examiner": "Dr. Emily Johnson",
    "location": "Ward A",
    "reasonForVisit": "Pneumonia treatment and monitoring"
  }
}
EOF
)
hr_couch_delete "visit_p1_200001"
hr_couch_put "visit_p1_200001" "$VISIT_DOC"

# 5. Record Initial State for Anti-Gaming
# Get the _rev of the visit we just created
VISIT_REV=$(hr_couch_get "visit_p1_200001" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$VISIT_REV" > /tmp/initial_visit_rev.txt
echo "Initial Visit Rev: $VISIT_REV"

date +%s > /tmp/task_start_time.txt

# 6. Prepare Browser
echo "Launching Firefox..."
# Kill old instances
pkill -f firefox || true
sleep 1

# Start Firefox and Login
# The ensure_hospitalrun_logged_in helper handles opening, maximizing, and logging in
ensure_hospitalrun_logged_in

# Navigate to Patient List to start
navigate_firefox_to "http://localhost:3000/#/patients"

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="