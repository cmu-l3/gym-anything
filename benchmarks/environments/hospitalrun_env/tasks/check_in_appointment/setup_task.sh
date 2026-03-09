#!/bin/bash
echo "=== Setting up check_in_appointment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 2. Seed Patient: Alice Johnson
echo "Seeding patient Alice Johnson..."
# ID: patient_p1_alicejohnson
# Note: HospitalRun expects data wrapped in a "data" property
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_alicejohnson" \
    -H "Content-Type: application/json" \
    -d '{
    "data": {
        "friendlyId": "P00099",
        "firstName": "Alice",
        "lastName": "Johnson",
        "name": "Alice Johnson",
        "sex": "Female",
        "dateOfBirth": "1990-05-15",
        "phone": "555-0199",
        "email": "alice.j@example.com",
        "address": "123 Maple St",
        "patientType": "Charity",
        "type": "patient"
    }
}' > /dev/null || true

# 3. Seed Appointment: Today at 9:00 AM
# Calculate today's date in MM/DD/YYYY format
TODAY=$(date +%m/%d/%Y)
# Use a timestamp for the ID to ensure uniqueness if needed, or fixed ID
APPT_ID="appointment_p1_alice_9am"

# Calculate timestamps for start/end (epoch ms)
# 9:00 AM today
START_TS=$(date -d "today 09:00" +%s)000
END_TS=$(date -d "today 09:30" +%s)000

echo "Seeding appointment for $TODAY at 9:00 AM..."

curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${APPT_ID}" \
    -H "Content-Type: application/json" \
    -d "{
    \"data\": {
        \"startDate\": ${START_TS},
        \"endDate\": ${END_TS},
        \"title\": \"General Checkup\",
        \"allDay\": false,
        \"patient\": \"patient_p1_alicejohnson\",
        \"provider\": \"Dr. Test\",
        \"location\": \"Room 101\",
        \"status\": \"Scheduled\",
        \"visitType\": \"General Checkup\",
        \"type\": \"appointment\"
    }
}" > /dev/null || true

# 4. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate to Appointments page to start
navigate_firefox_to "http://localhost:3000/#/appointments"
sleep 5

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="