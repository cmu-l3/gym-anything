#!/bin/bash
set -e
echo "=== Setting up cancel_surgical_plan task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Verify HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Seed Patient: Oliver Twist (P00501)
# We use a specific ID to ensure we can target it reliably
PATIENT_ID="patient_p1_00501"
echo "Seeding patient Oliver Twist ($PATIENT_ID)..."

# Check if patient exists, if not create
EXISTING_PATIENT=$(hr_couch_get "$PATIENT_ID" | grep "_rev" || echo "")
if [ -z "$EXISTING_PATIENT" ]; then
    hr_couch_put "$PATIENT_ID" '{
      "data": {
        "friendlyId": "P00501",
        "displayName": "Twist, Oliver",
        "firstName": "Oliver",
        "lastName": "Twist",
        "sex": "Male",
        "dateOfBirth": "05/15/2010",
        "bloodType": "A+",
        "status": "Active",
        "address": "123 Orphanage Rd, London, UK",
        "phone": "555-0199",
        "email": "oliver.twist@example.com",
        "patientType": "Outpatient"
      }
    }'
else
    echo "Patient already exists."
fi

# 3. Seed Operative Plan: Inguinal Hernia Repair
# We use a deterministic ID to make verification easier
PLAN_ID="operativePlan_p1_00501_target_plan"
echo "Seeding operative plan ($PLAN_ID)..."

# Delete existing plan if it exists to ensure fresh state (Planned status)
hr_couch_delete "$PLAN_ID"
sleep 1

# Create the plan with "Planned" status
# Note: HospitalRun expects dates in ISO format or specific strings.
NEXT_WEEK_ISO=$(date -d "+7 days" -Iseconds)

hr_couch_put "$PLAN_ID" "{
  "data": {
    "patient": \"$PATIENT_ID\",
    "operationDescription": \"Inguinal Hernia Repair\",
    "surgeon": \"Dr. Smith\",
    "diagnosis": \"Right Inguinal Hernia\",
    "status": \"Planned\",
    "operationDate": \"$NEXT_WEEK_ISO\",
    "admissionInstructions": \"NPO after midnight.\",
    "caseComplexity": \"Intermediate\",
    "type": \"operativePlan\"
  }
}"

# 4. Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 5. Wait for PouchDB to sync and App to be ready
echo "Waiting for DB sync..."
wait_for_db_ready

# 6. Navigate to Patients list as starting point
echo "Navigating to Patients list..."
navigate_firefox_to "http://localhost:3000/#/patients"

# 7. Capture initial state
take_screenshot /tmp/task_initial.png
echo "Initial state captured."

echo "=== Task setup complete ==="