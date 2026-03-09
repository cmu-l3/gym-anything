#!/bin/bash
echo "=== Setting up return_medication task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Wait for HospitalRun to be ready
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 3. Seed Patient: Marcus Williams
# We use a specific ID to ensure consistency
echo "Seeding patient Marcus Williams..."
PATIENT_DOC=$(cat <<EOF
{
  "type": "patient",
  "patientId": "P01087",
  "data": {
    "firstName": "Marcus",
    "lastName": "Williams",
    "friendlyId": "P01087",
    "dateOfBirth": "1978-08-22T00:00:00.000Z",
    "sex": "Male",
    "phone": "(555) 234-8901",
    "address": "742 Elm Street, Springfield, IL 62704",
    "patientType": "Inpatient",
    "status": "Active"
  }
}
EOF
)
# Delete if exists to ensure clean state
hr_couch_delete "patient_p1_marcus" 2>/dev/null || true
hr_couch_put "patient_p1_marcus" "$PATIENT_DOC"

# 4. Seed Fulfilled Medication: Amoxicillin
# Returns usually require an existing fulfilled order
echo "Seeding medication order..."
MED_DOC=$(cat <<EOF
{
  "type": "medication",
  "status": "Fulfilled",
  "data": {
    "medication": "Amoxicillin 500mg Capsule",
    "patient": "patient_p1_marcus",
    "status": "Fulfilled",
    "prescription": "Take 1 capsule by mouth three times daily for 7 days",
    "quantity": 21,
    "refills": 0,
    "prescriptionDate": "2025-01-20T09:00:00.000Z",
    "requestedBy": "hradmin",
    "requestedDate": "2025-01-20T09:00:00.000Z",
    "fulfillmentDate": "2025-01-20T10:00:00.000Z",
    "visit": "visit_p1_marcus_initial"
  }
}
EOF
)
hr_couch_delete "medication_p1_amox_marcus" 2>/dev/null || true
hr_couch_put "medication_p1_amox_marcus" "$MED_DOC"

# 5. Record initial document count (to detect new documents later)
TOTAL_DOCS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs" | jq '.total_rows')
echo "$TOTAL_DOCS" > /tmp/initial_doc_count.txt

# 6. Ensure Firefox is open and logged in
ensure_hospitalrun_logged_in

# 7. Navigate to Medication section (or Dashboard)
# We'll start at the dashboard to make the agent navigate
navigate_firefox_to "http://localhost:3000"

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="