#!/bin/bash
set -e
echo "=== Setting up Cancel Lab Request Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is ready
echo "Waiting for HospitalRun..."
for i in {1..30}; do
    if curl -s http://localhost:3000 >/dev/null; then
        echo "HospitalRun is reachable."
        break
    fi
    sleep 2
done

# 2. Setup Data: Create Patients and Lab Requests directly in CouchDB

# Patient 1: Tanya Bleecker (Target)
echo "Seeding Target Patient (Tanya Bleecker)..."
PATIENT1_ID="patient_p1_P00555"
PATIENT1_DOC=$(cat <<EOF
{
  "type": "patient",
  "data": {
    "firstName": "Tanya",
    "lastName": "Bleecker",
    "sex": "Female",
    "dateOfBirth": "1982-05-15T00:00:00.000Z",
    "patientId": "P00555",
    "address": "123 Maple Ave",
    "phone": "555-0199",
    "email": "tanya.b@example.com",
    "patientType": "Outpatient"
  }
}
EOF
)
hr_couch_put "${PATIENT1_ID}" "${PATIENT1_DOC}"

# Patient 2: John Doe (Control)
echo "Seeding Control Patient (John Doe)..."
PATIENT2_ID="patient_p1_P00999"
PATIENT2_DOC=$(cat <<EOF
{
  "type": "patient",
  "data": {
    "firstName": "John",
    "lastName": "Doe",
    "sex": "Male",
    "dateOfBirth": "1990-01-01T00:00:00.000Z",
    "patientId": "P00999",
    "patientType": "Outpatient"
  }
}
EOF
)
hr_couch_put "${PATIENT2_ID}" "${PATIENT2_DOC}"

# Target Lab Request (Lipid Panel for Tanya)
# Note: HospitalRun uses type "lab" or "imaging" typically.
TARGET_REQ_ID="lab_p1_REQ001"
echo "Seeding Target Lab Request (${TARGET_REQ_ID})..."
TARGET_REQ_DOC=$(cat <<EOF
{
  "type": "lab",
  "data": {
    "selectPatient": {
      "id": "${PATIENT1_ID}",
      "firstName": "Tanya",
      "lastName": "Bleecker",
      "patientId": "P00555"
    },
    "patientId": "P00555",
    "visitId": "",
    "labType": "Lipid Panel",
    "status": "Requested",
    "requestDate": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
    "notes": "Erroneous duplicate order - needs cancellation"
  }
}
EOF
)
hr_couch_put "${TARGET_REQ_ID}" "${TARGET_REQ_DOC}"

# Control Lab Request (CBC for John Doe)
CONTROL_REQ_ID="lab_p1_REQ002"
echo "Seeding Control Lab Request (${CONTROL_REQ_ID})..."
CONTROL_REQ_DOC=$(cat <<EOF
{
  "type": "lab",
  "data": {
    "selectPatient": {
      "id": "${PATIENT2_ID}",
      "firstName": "John",
      "lastName": "Doe",
      "patientId": "P00999"
    },
    "patientId": "P00999",
    "visitId": "",
    "labType": "CBC",
    "status": "Requested",
    "requestDate": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
    "notes": "Valid order - do not touch"
  }
}
EOF
)
hr_couch_put "${CONTROL_REQ_ID}" "${CONTROL_REQ_DOC}"

# 3. Prepare Browser
echo "Preparing Firefox..."
# Ensure offline sync fix is applied so DB loads correctly
fix_offline_sync
# Ensure logged in and kill old instances
ensure_hospitalrun_logged_in

# Navigate to Labs section
echo "Navigating to Labs section..."
navigate_firefox_to "http://localhost:3000/#/labs"

# Wait for page load
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task Setup Complete ==="