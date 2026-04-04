#!/bin/bash
echo "=== Setting up reassign_appointment_provider task ==="

source /workspace/scripts/task_utils.sh

# 1. Verify HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Record Start Time and Anti-Gaming info
date +%s > /tmp/task_start_time.txt

# 3. Ensure Patient "Maria Santos" exists
# (Using seeded ID patient_p1_0001)
PATIENT_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_0001" 2>/dev/null || echo "")
if [[ $PATIENT_DOC == *"error"* ]] || [[ -z $PATIENT_DOC ]]; then
    echo "Seeding patient Maria Santos..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_0001" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00001",
            "displayName": "Santos, Maria",
            "firstName": "Maria",
            "lastName": "Santos",
            "sex": "Female",
            "dateOfBirth": "1985-03-15",
            "phone": "555-0199",
            "email": "maria.santos@example.com",
            "patientType": "Outpatient"
          },
          "type": "patient"
        }' > /dev/null || true
fi

# 4. Calculate Dates (Tomorrow 10:00 AM)
# HospitalRun often uses ISO 8601 timestamps (ms) for sorting, but stores Date objects in data
# We'll use a fixed future date relative to now to ensure it's "upcoming"
# Using python to get milliseconds for tomorrow 10:00 AM
DATES_JSON=$(python3 -c '
import datetime
import time

now = datetime.datetime.now()
tomorrow = now + datetime.timedelta(days=1)
# Set to 10:00 AM
start_dt = tomorrow.replace(hour=10, minute=0, second=0, microsecond=0)
end_dt = start_dt + datetime.timedelta(minutes=30)

# Format for HospitalRun (usually stores timestamps in data)
print(f"{{\"start_ms\": {int(start_dt.timestamp() * 1000)}, \"end_ms\": {int(end_dt.timestamp() * 1000)}, \"iso_start\": \"{start_dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")}\", \"iso_end\": \"{end_dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")}\"}}")
')

START_MS=$(echo "$DATES_JSON" | jq -r .start_ms)
END_MS=$(echo "$DATES_JSON" | jq -r .end_ms)
ISO_START=$(echo "$DATES_JSON" | jq -r .iso_start)
ISO_END=$(echo "$DATES_JSON" | jq -r .iso_end)

echo "Scheduling appointment for tomorrow at 10:00 AM (Epoch: $START_MS)"

# 5. Seed the Appointment
# We explicitly set _id to "appointment_p1_taskseed" so we can find it easily later
# First, delete if exists (to reset state)
EXISTING_REV=$(curl -s -I -X HEAD "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/appointment_p1_taskseed" | grep -Fi ETag | awk '{print $2}' | tr -d '"\r' || echo "")
if [ -n "$EXISTING_REV" ]; then
    curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/appointment_p1_taskseed?rev=${EXISTING_REV}" > /dev/null
fi

# Create the appointment
# Provider: Dr. Emily Johnson
curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/appointment_p1_taskseed" \
    -H "Content-Type: application/json" \
    -d "{
      \"data\": {
        \"startDate\": $START_MS,
        \"endDate\": $END_MS,
        \"patient\": \"patient_p1_0001\",
        \"provider\": \"Dr. Emily Johnson\",
        \"location\": \"Clinic A\",
        \"appointmentType\": \"General Checkup\",
        \"reason\": \"Routine Follow-up\",
        \"status\": \"Scheduled\",
        \"allDay\": false,
        \"title\": \"Maria Santos - General Checkup\"
      },
      \"type\": \"appointment\"
    }" > /dev/null

# 6. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate to Appointments page
echo "Navigating to Appointments..."
wait_for_db_ready
navigate_firefox_to "http://localhost:3000/#/appointments"
sleep 5

# 7. Initial Screenshot
take_screenshot /tmp/reassign_initial.png
echo "Initial screenshot captured."

# Save seeded ID for export script
echo "appointment_p1_taskseed" > /tmp/task_appt_id.txt
echo "$START_MS" > /tmp/task_appt_start.txt

echo "=== Setup complete ==="