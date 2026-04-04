#!/bin/bash
echo "=== Setting up record_surgical_outcome task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for HospitalRun to be ready
echo "Checking HospitalRun availability..."
wait_for_db_ready

# 2. Seed Patient: Lucas Silva
# We use a fixed ID to make verification reliable
PATIENT_ID="patient_p1_lucassilva"
echo "Seeding patient $PATIENT_ID..."

# Delete if exists (clean state)
hr_couch_delete "$PATIENT_ID"

# Create Patient Doc
PATIENT_DOC=$(cat <<EOF
{
  "data": {
    "friendlyId": "P-LUCAS",
    "firstName": "Lucas",
    "lastName": "Silva",
    "sex": "Male",
    "dateOfBirth": "1980-05-15T00:00:00.000Z",
    "status": "Active",
    "address": "123 Samba Lane",
    "phone": "555-0199",
    "patientType": "Patient"
  },
  "type": "patient"
}
EOF
)
hr_couch_put "$PATIENT_ID" "$PATIENT_DOC"

# 3. Seed Operative Plan: Inguinal Hernia Repair (Planned)
PLAN_ID="operative_plan_p1_lucassilva_hernia"
echo "Seeding operative plan $PLAN_ID..."

# Delete if exists
hr_couch_delete "$PLAN_ID"

# Calculate date for tomorrow (Scheduled)
TOMORROW=$(date -d "+1 day" +%Y-%m-%dT10:00:00.000Z)

# Create Plan Doc
# Note: linking to patient via 'patient' field in data object
PLAN_DOC=$(cat <<EOF
{
  "data": {
    "patient": "$PATIENT_ID",
    "operationDescription": "Inguinal Hernia Repair",
    "diagnosis": "Right Inguinal Hernia",
    "surgeon": "Dr. Chen",
    "status": "Planned",
    "operationDate": "$TOMORROW",
    "notes": "Routine repair scheduled."
  },
  "type": "operativePlan"
}
EOF
)
hr_couch_put "$PLAN_ID" "$PLAN_DOC"

# 4. Record Initial State for Anti-Gaming
# We capture the initial revision (_rev) of the plan.
# If the agent modifies the doc, _rev will change.
INITIAL_PLAN_JSON=$(hr_couch_get "$PLAN_ID")
INITIAL_REV=$(echo "$INITIAL_PLAN_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")

echo "Initial Plan Rev: $INITIAL_REV"
echo "$INITIAL_REV" > /tmp/initial_plan_rev.txt
date +%s > /tmp/task_start_time.txt

# 5. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate to Patient List to start
navigate_firefox_to "http://localhost:3000/#/patients"

# 6. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="