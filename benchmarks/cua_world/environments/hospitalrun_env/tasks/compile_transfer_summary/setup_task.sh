#!/bin/bash
echo "=== Setting up compile_transfer_summary task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts
rm -f /home/ga/transfer_summary.txt
rm -f /tmp/task_result.json

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure HospitalRun is accessible
echo "Checking HospitalRun availability..."
wait_for_couchdb 30
wait_for_hospitalrun 30

# 4. Seed Patient Data (Walter Bishop)
# We use curl to inject directly into CouchDB to ensure the data exists exactly as needed.
# ID: patient_p1_wb001
echo "Seeding patient record..."
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_wb001" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "friendlyId": "P_WB001",
        "firstName": "Walter",
        "lastName": "Bishop",
        "sex": "Male",
        "dateOfBirth": "1946-08-20",
        "bloodType": "A+",
        "status": "Active",
        "address": "Harvard University, Lab 1, Cambridge, MA",
        "phone": "617-555-0199",
        "email": "walter.bishop@example.com",
        "patientType": "Inpatient",
        "allergies": "Penicillin (Hives), Strawberries (Rash)"
      }
    }' > /dev/null || true

# 5. Seed Medications
# Note: HospitalRun Medication documents are linked to the patient via 'patient' field.

# Active Med 1: Digoxin
echo "Seeding Digoxin (Active)..."
curl -s -X POST "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "type": "medication",
        "patient": "patient_p1_wb001",
        "medicationName": "Digoxin",
        "dosage": "0.125mg",
        "frequency": "Daily",
        "status": "Active",
        "requestedBy": "Dr. Bell",
        "requestedOn": "2025-01-01"
      }
    }' > /dev/null

# Active Med 2: Warfarin
echo "Seeding Warfarin (Active)..."
curl -s -X POST "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "type": "medication",
        "patient": "patient_p1_wb001",
        "medicationName": "Warfarin",
        "dosage": "5mg",
        "frequency": "Daily",
        "status": "Active",
        "requestedBy": "Dr. Bell",
        "requestedOn": "2025-01-01"
      }
    }' > /dev/null

# Inactive Med 3: Amoxicillin (Completed) -> SHOULD NOT BE IN SUMMARY
echo "Seeding Amoxicillin (Completed)..."
curl -s -X POST "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "type": "medication",
        "patient": "patient_p1_wb001",
        "medicationName": "Amoxicillin",
        "dosage": "500mg",
        "frequency": "TID",
        "status": "Completed",
        "requestedBy": "Dr. Bell",
        "requestedOn": "2024-06-01",
        "completedOn": "2024-06-10"
      }
    }' > /dev/null

# 6. Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 7. Navigate to Patients list to start the flow
navigate_firefox_to "http://localhost:3000/#/patients"

# 8. Initial Screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="