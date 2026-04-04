#!/bin/bash
echo "=== Setting up renew_medication_order task ==="

source /workspace/scripts/task_utils.sh

# Record start time
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

# 2. Seed Patient "Martha Kent"
PATIENT_ID="patient_p1_000006"
echo "Seeding patient Martha Kent..."

# Check if exists, if not create
PATIENT_CHECK=$(hr_couch_get "$PATIENT_ID")
if echo "$PATIENT_CHECK" | grep -q "error"; then
    hr_couch_put "$PATIENT_ID" '{
        "data": {
            "friendlyId": "P006",
            "firstName": "Martha",
            "lastName": "Kent",
            "sex": "Female",
            "dateOfBirth": "1955-05-12",
            "address": "45 Smallville Lane",
            "phone": "555-0199",
            "patientType": "Outpatient",
            "status": "Active"
        }
    }'
    echo "Patient Martha Kent created."
else
    echo "Patient Martha Kent already exists."
fi

# 3. Seed EXPIRED Medication Order (The "Hidden" Info)
# Amlodipine 5mg, Daily, Status: Completed
HISTORICAL_ORDER_ID="medication_p1_000006_old"
echo "Seeding historical expired medication..."

# Calculate dates
DATE_PREV_START=$(date -d "60 days ago" +%s)000
DATE_PREV_END=$(date -d "30 days ago" +%s)000

# HospitalRun medication object structure
# Note: In HR v1, medication is often a separate doc type 'medication' or embedded.
# We will create a standalone medication document linked to the patient.
hr_couch_put "$HISTORICAL_ORDER_ID" "{
    \"data\": {
        \"patient\": \"$PATIENT_ID\",
        \"medication\": \"Amlodipine\",
        \"inventoryItem\": \"Amlodipine\",
        \"prescription\": \"5mg\",
        \"quantity\": \"30\",
        \"refills\": \"0\",
        \"frequency\": \"Daily\",
        \"startDate\": $DATE_PREV_START,
        \"endDate\": $DATE_PREV_END,
        \"status\": \"Completed\",
        \"orderedBy\": \"Dr. Fate\",
        \"priority\": \"Routine\"
    }
}"

echo "Expired medication order seeded."

# 4. Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 5. Wait for DB sync
wait_for_db_ready

# 6. Navigate to Patients list to start
echo "Navigating to Patients list..."
navigate_firefox_to "http://localhost:3000/#/patients"

# Take initial screenshot
take_screenshot /tmp/renew_med_initial.png

echo "=== Setup complete ==="