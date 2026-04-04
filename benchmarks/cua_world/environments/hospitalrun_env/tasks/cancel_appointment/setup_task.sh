#!/bin/bash
set -e
echo "=== Setting up cancel_appointment task ==="

source /workspace/scripts/task_utils.sh

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

# 2. Define IDs
PATIENT_ID="patient_p1_tbaker"
APPT_ID="appointment_p1_tbaker_checkup"
TIMESTAMP=$(date +%s)

# 3. Create Patient: Thomas Baker
echo "Creating/Resetting patient Thomas Baker..."
# Delete if exists
hr_couch_delete "$PATIENT_ID" || true

# Create patient
PATIENT_DOC=$(cat <<EOF
{
  "data": {
    "firstName": "Thomas",
    "lastName": "Baker",
    "sex": "Male",
    "dateOfBirth": "1980-05-15",
    "phone": "555-0199",
    "address": "123 Maple Ave",
    "patientType": "Patient",
    "status": "Active"
  }
}
EOF
)
hr_couch_put "$PATIENT_ID" "$PATIENT_DOC"

# 4. Create Appointment: General Checkup (Tomorrow 10am)
echo "Creating/Resetting scheduled appointment..."
# Delete if exists
hr_couch_delete "$APPT_ID" || true

# Calculate dates
TOMORROW_START=$(date -d "tomorrow 10:00" +%s)000
TOMORROW_END=$(date -d "tomorrow 10:30" +%s)000

# Create appointment linked to patient
# Note: HospitalRun uses 'patient' field in appointment data to link, usually matching the patient ID
APPT_DOC=$(cat <<EOF
{
  "data": {
    "title": "General Checkup",
    "patient": "$PATIENT_ID",
    "startDate": $TOMORROW_START,
    "endDate": $TOMORROW_END,
    "location": "Main Clinic",
    "appointmentType": "Outpatient",
    "status": "Scheduled",
    "notes": "Regular annual physical",
    "examiner": "Dr. Smith"
  }
}
EOF
)
hr_couch_put "$APPT_ID" "$APPT_DOC"

# Store ID for export script
echo "$APPT_ID" > /tmp/target_appt_id.txt

# 5. Launch Firefox and Login
# This helper handles PouchDB sync issues and logs in as admin
ensure_hospitalrun_logged_in

# 6. Navigate to Appointments
wait_for_db_ready
echo "Navigating to Appointments list..."
navigate_firefox_to "http://localhost:3000/#/appointments"
sleep 5

# 7. Initial Screenshot
take_screenshot /tmp/cancel_appointment_initial.png
echo "Initial state screenshot captured."

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="