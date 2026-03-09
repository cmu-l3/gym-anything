#!/bin/bash
set -e
echo "=== Setting up update_imaging_indication task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Seed Patient "Gregory Peck"
# ID: patient_p1_gregory
echo "Seeding patient Gregory Peck..."
PATIENT_DOC='{
  "data": {
    "friendlyId": "P_GREGORY",
    "displayName": "Peck, Gregory",
    "firstName": "Gregory",
    "lastName": "Peck",
    "sex": "Male",
    "dateOfBirth": "1950-04-05",
    "bloodType": "O+",
    "status": "Active",
    "address": "123 Hollywood Blvd",
    "phone": "555-0199",
    "email": "gregory.peck@example.com",
    "patientType": "Outpatient"
  }
}'

# Check if patient exists, if so, ensure details are correct (overwrite)
# We use a PUT to specific ID to ensure it exists
hr_couch_put "patient_p1_gregory" "$PATIENT_DOC"

# 3. Seed Imaging Request with "Cough"
# ID: imaging_p1_gregory_req1
# HospitalRun imaging requests usually look like:
# {
#   "type": "imaging",
#   "data": {
#     "selectPatient": { ...patient summary... },
#     "patientId": "patient_p1_gregory",
#     "imagingType": "Chest X-ray",
#     "notes": "Cough",
#     "status": "Requested",
#     "requestedDate": ...
#   }
# }
# Note: selectPatient structure helps the UI display the name without fetching the patient doc immediately.

echo "Seeding Imaging Request..."
IMAGING_DOC='{
  "data": {
    "patient": "patient_p1_gregory",
    "patientId": "patient_p1_gregory",
    "selectPatient": {
      "id": "patient_p1_gregory",
      "displayName": "Peck, Gregory"
    },
    "imagingType": "Chest X-ray",
    "notes": "Cough",
    "status": "Requested",
    "requestedDate": "2025-05-10T10:00:00.000Z",
    "requestedBy": "Dr. Smith"
  }
}'

# Clean up existing request to ensure clean state (force overwrite)
# We need to get rev to delete or update. Put helper handles update if we don't supply _rev?
# Actually, hr_couch_put usually overwrites if we don't provide _rev, but CouchDB requires _rev for updates.
# Let's try to delete first.
hr_couch_delete "imaging_p1_gregory_req1"
sleep 1
hr_couch_put "imaging_p1_gregory_req1" "$IMAGING_DOC"

# 4. Record Initial State (Revision)
# We need this to verify that the agent *modified* the document, not just that it exists.
sleep 2
DOC_JSON=$(hr_couch_get "imaging_p1_gregory_req1")
INITIAL_REV=$(echo "$DOC_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$INITIAL_REV" > /tmp/initial_imaging_rev.txt
echo "Initial revision recorded: $INITIAL_REV"

# 5. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate to Imaging list to make it easier (or Dashboard)
# Let's start at Imaging list to save some search time, or Dashboard to test navigation.
# Dashboard is better for "medium" difficulty.
navigate_firefox_to "http://localhost:3000"
wait_for_db_ready

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="