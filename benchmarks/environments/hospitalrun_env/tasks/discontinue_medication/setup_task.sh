#!/bin/bash
echo "=== Setting up discontinue_medication task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
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

# 2. Ensure Patient 'Maria Santos' exists
# We'll use a specific ID to ensure consistency: patient_p1_mariasantos
PATIENT_ID="patient_p1_mariasantos"
echo "Seeding patient Maria Santos..."

curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "friendlyId": "P00999",
        "displayName": "Santos, Maria",
        "firstName": "Maria",
        "lastName": "Santos",
        "sex": "Female",
        "dateOfBirth": "1990-05-15",
        "bloodType": "A+",
        "status": "Active",
        "address": "123 Ocean Drive, Miami, FL",
        "phone": "555-0199",
        "email": "maria.santos@example.com",
        "patientType": "Outpatient"
      }
    }' > /dev/null || true

# 3. Ensure Active Medication Order exists
# We need to make sure there is an active order to discontinue.
# ID: medication_p1_mariasantos_amox
MED_ID="medication_p1_mariasantos_amox"
echo "Seeding active medication order..."

# We delete first to ensure it's in a clean "Active" state and not already canceled from a previous run
REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${MED_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
if [ -n "$REV" ]; then
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${MED_ID}?rev=${REV}" > /dev/null
fi

# Create the active medication
# Note: HospitalRun logic often looks for specific structure.
# We set status to 'Active'.
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${MED_ID}" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "patient": "patient_p1_mariasantos",
        "medication": "Amoxicillin 500mg",
        "prescription": "Amoxicillin 500mg",
        "status": "Active",
        "priority": "Routine",
        "startDate": "2025-01-01",
        "quantity": "20",
        "refills": "0",
        "notes": "Take with food",
        "orderedBy": "Dr. Chen",
        "visit": "visit_p1_mariasantos_01" 
      }
    }' > /dev/null || true

# 4. Ensure Firefox is open and ready
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for DB sync
wait_for_db_ready

# Navigate to Patient List to start the agent there
echo "Navigating to Patient List..."
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# Capture Initial State
take_screenshot /tmp/task_initial.png
echo "Initial state captured."

echo "=== Task Setup Complete ==="