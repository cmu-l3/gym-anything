#!/bin/bash
echo "=== Setting up consolidate_duplicate_patients task ==="

source /workspace/scripts/task_utils.sh

# Record start time
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

# ------------------------------------------------------------------
# SEED DATA
# ------------------------------------------------------------------
echo "Seeding patient records..."

# 1. Master Record (P00801) - Has Address, NO Phone
# We delete first to ensure clean state
hr_couch_delete "patient_p1_P00801"
sleep 1

curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00801" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "friendlyId": "P00801",
        "displayName": "Chen, Michael",
        "firstName": "Michael",
        "lastName": "Chen",
        "sex": "Male",
        "dateOfBirth": "05/12/1980",
        "bloodType": "A+",
        "status": "Active",
        "address": "452 Oak Avenue, Seattle, WA 98101",
        "phone": "",
        "email": "mchen80@example.com",
        "patientType": "Outpatient"
      },
      "type": "patient"
    }' > /dev/null
echo "Seeded Master Record (P00801)"

# 2. Duplicate Record (P00802) - Has Phone, NO Address
hr_couch_delete "patient_p1_P00802"
sleep 1

curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00802" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "friendlyId": "P00802",
        "displayName": "Chen, Michael",
        "firstName": "Michael",
        "lastName": "Chen",
        "sex": "Male",
        "dateOfBirth": "05/12/1980",
        "status": "Active",
        "address": "",
        "phone": "555-0199",
        "email": "",
        "patientType": "Outpatient"
      },
      "type": "patient"
    }' > /dev/null
echo "Seeded Duplicate Record (P00802)"

# ------------------------------------------------------------------
# BROWSER SETUP
# ------------------------------------------------------------------

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for PouchDB sync
wait_for_db_ready

# Navigate to Patients list to start
echo "Navigating to Patient List..."
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Setup complete ==="