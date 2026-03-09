#!/bin/bash
echo "=== Setting up add_patient_insurance task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# Ensure patient Lucas Silva exists and has NO insurance data (clean state)
echo "Preparing patient record for Lucas Silva (P00008)..."

# Define the seed document without insurance
# Note: HospitalRun stores most data in a 'data' property
LUCAS_DOC='{
  "data": {
    "friendlyId": "P00008",
    "displayName": "Silva, Lucas",
    "firstName": "Lucas",
    "lastName": "Silva",
    "sex": "Male",
    "dateOfBirth": "05/14/1982",
    "bloodType": "A+",
    "status": "Active",
    "address": "789 Pine Avenue, Portland, OR 97204",
    "phone": "503-555-0199",
    "email": "lucas.silva@example.com",
    "patientType": "Outpatient"
  }
}'

# Check if document exists
DOC_ID="patient_p1_000008"
EXISTING_REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${DOC_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))" 2>/dev/null || echo "")

if [ -n "$EXISTING_REV" ]; then
    echo "Updating existing patient record (clearing insurance)..."
    # We use the seed doc but need to include the _rev to update
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${DOC_ID}" \
        -H "Content-Type: application/json" \
        -d "$(echo "$LUCAS_DOC" | jq --arg rev "$EXISTING_REV" '. + {_rev: $rev}')" > /dev/null
else
    echo "Creating new patient record..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${DOC_ID}" \
        -H "Content-Type: application/json" \
        -d "$LUCAS_DOC" > /dev/null
fi

# Store the initial revision to check for updates later
NEW_REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${DOC_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$NEW_REV" > /tmp/initial_rev.txt

# Ensure Firefox is open and on HospitalRun
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for PouchDB to sync
wait_for_db_ready

# Navigate to patients list
navigate_firefox_to "http://localhost:3000/#/patients"

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot captured."

echo "=== Task setup complete ==="