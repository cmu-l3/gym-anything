#!/bin/bash
set -e
echo "=== Setting up transfer_patient_ward task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is accessible
echo "Waiting for HospitalRun..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ >/dev/null; then
        echo "HospitalRun is up."
        break
    fi
    sleep 2
done

# 2. Seed Data: Patient Li Wei and his Visit
# We use specific IDs to make verification reliable.

# Define Documents
PATIENT_DOC='{
  "data": {
    "friendlyId": "P-LIWEI",
    "firstName": "Li",
    "lastName": "Wei",
    "sex": "Male",
    "dateOfBirth": "1965-03-12",
    "status": "Active",
    "address": "123 Main St, Beijing",
    "phone": "555-0199",
    "email": "li.wei@example.com",
    "patientType": "Inpatient",
    "type": "patient"
  }
}'

# Note: The visit MUST be linked to the patient via the 'patient' field.
# We set location to 'General Ward' initially.
VISIT_DOC='{
  "data": {
    "visitType": "Inpatient",
    "patient": "patient_p1_liwei",
    "startDate": "2025-01-12T08:00:00.000Z",
    "endDate": "",
    "reasonForVisit": "Severe Pneumonia",
    "location": "General Ward",
    "status": "Admitted",
    "examiner": "Dr. Zhang",
    "type": "visit"
  }
}'

echo "Seeding/Resetting Patient Data..."

# Delete existing docs if they exist to ensure clean state
hr_couch_delete "patient_p1_liwei" || true
hr_couch_delete "visit_p1_liwei_001" || true

# Create Patient
hr_couch_put "patient_p1_liwei" "$PATIENT_DOC"
echo "Patient created."

# Create Visit
hr_couch_put "visit_p1_liwei_001" "$VISIT_DOC"
echo "Visit created with location: General Ward"

# 3. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate to Patients list to start
navigate_firefox_to "http://localhost:3000/#/patients"

# 4. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="