#!/bin/bash
set -e
echo "=== Setting up Delete Patient Record Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# 1. Apply offline sync fix to ensure app works correctly
fix_offline_sync

# 2. Ensure HospitalRun is accessible
echo "Waiting for HospitalRun..."
for i in {1..30}; do
    if curl -s http://localhost:3000 > /dev/null; then
        echo "HospitalRun is up."
        break
    fi
    sleep 2
done

# 3. Seed Control Patient (Elena Vasquez) - Should NOT be deleted
echo "Seeding control patient..."
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00100" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "friendlyId": "P00100",
        "firstName": "Elena",
        "lastName": "Vasquez",
        "sex": "Female",
        "dateOfBirth": "1990-05-15",
        "phone": "555-0100",
        "address": "100 Control Way",
        "patientType": "Outpatient"
      }
    }' > /dev/null || true

# 4. Seed Target Patient (Marcus Wellington) - MUST be deleted
echo "Seeding target patient..."
# First delete if exists to ensure clean state
REV=$(curl -s -I "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00300" | grep -Fi Etag | awk -F'"' '{print $2}')
if [ -n "$REV" ]; then
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00300?rev=${REV}" > /dev/null
fi

# Create fresh record
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00300" \
    -H "Content-Type: application/json" \
    -d '{
      "data": {
        "friendlyId": "P00300",
        "firstName": "Marcus",
        "lastName": "Wellington",
        "sex": "Male",
        "dateOfBirth": "1978-11-02",
        "phone": "860-555-0147",
        "address": "47 Birchwood Lane, Hartford, CT 06103",
        "patientType": "Outpatient",
        "notes": "Test record for deletion task"
      }
    }' > /dev/null

# Verify target exists
if curl -s -f "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_P00300" > /dev/null; then
    echo "Target patient P00300 confirmed created."
    echo "true" > /tmp/target_existed_at_start.txt
else
    echo "ERROR: Failed to seed target patient."
    exit 1
fi

# 5. Launch Browser and Login
echo "Launching Firefox..."
ensure_hospitalrun_logged_in

# Navigate to Patient List to ensure data is loaded
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="