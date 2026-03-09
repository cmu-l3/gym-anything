#!/bin/bash
echo "=== Setting up document_pain_assessment task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for HospitalRun/CouchDB
wait_for_db_ready

# 2. Seed Custom Form: "Pain Assessment"
# This is critical so the form appears in the UI
echo "Seeding 'Pain Assessment' custom form..."
hr_couch_put "custom_form_pain_assessment" '{
  "data": {
    "name": "Pain Assessment",
    "formType": "Visit",
    "type": "custom_form",
    "columns": [
      {
        "label": "Pain Score (0-10)",
        "type": "select",
        "property": "painScore",
        "values": "0,1,2,3,4,5,6,7,8,9,10"
      },
      {
        "label": "Location",
        "type": "text",
        "property": "location"
      },
      {
        "label": "Duration",
        "type": "text",
        "property": "duration"
      },
      {
        "label": "Aggravating Factors",
        "type": "textarea",
        "property": "aggravatingFactors"
      }
    ]
  }
}'

# 3. Seed Patient: "Lars Jensen"
echo "Seeding patient Lars Jensen..."
# Ensure no stale data
hr_couch_delete "patient_p1_000100"

hr_couch_put "patient_p1_000100" '{
  "data": {
    "friendlyId": "P00100",
    "firstName": "Lars",
    "lastName": "Jensen",
    "sex": "Male",
    "dateOfBirth": "05/15/1980",
    "status": "Active",
    "patientType": "Outpatient",
    "phone": "555-0199",
    "address": "42 Nordic Way",
    "type": "patient"
  }
}'

# 4. Seed Active Visit
echo "Seeding active outpatient visit..."
TODAY=$(date +"%m/%d/%Y")
hr_couch_delete "visit_p1_000100_01"

hr_couch_put "visit_p1_000100_01" "{
  \"data\": {
    \"patient\": \"patient_p1_000100\",
    \"visitType\": \"Outpatient\",
    \"startDate\": \"$TODAY\",
    \"endDate\": \"$TODAY\",
    \"examiner\": \"Dr. Smith\",
    \"location\": \"General Clinic\",
    \"reasonForVisit\": \"Recurring back pain\",
    \"status\": \"Active\",
    \"type\": \"visit\"
  }
}"

# 5. Prepare Browser
echo "Launching browser and logging in..."
ensure_hospitalrun_logged_in

# Navigate to Patients list to start
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="