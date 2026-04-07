#!/bin/bash
echo "=== Setting up schedule_appointment task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh
wait_for_postgres

# 1. Record initial appointment count
INITIAL_COUNT=$(get_appointment_count)
echo "Initial appointment count: $INITIAL_COUNT"
rm -f /tmp/initial_appointment_count.txt 2>/dev/null || true
echo "$INITIAL_COUNT" > /tmp/initial_appointment_count.txt
chmod 666 /tmp/initial_appointment_count.txt 2>/dev/null || true

# 2. Remove existing appointment for Ana Betz on 2027-03-15 if it exists
# party_party has 'name' (first name) and 'lastname' as separate columns
PATIENT_ID=$(gnuhealth_db_query "SELECT gp.id FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%' LIMIT 1" | tr -d '[:space:]')
echo "Ana Betz patient_id: $PATIENT_ID"
if [ -n "$PATIENT_ID" ]; then
    EXISTING_APPT=$(gnuhealth_db_query "SELECT id FROM gnuhealth_appointment WHERE patient = $PATIENT_ID AND appointment_date::date = '2027-03-15' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$EXISTING_APPT" ]; then
        echo "Removing existing appointment (id=$EXISTING_APPT) for clean test"
        gnuhealth_db_query "DELETE FROM gnuhealth_appointment WHERE id = $EXISTING_APPT" 2>/dev/null || true
    fi
fi

# 3. Verify Ana Betz patient exists in the demo DB
ANA_EXISTS=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'" | tr -d '[:space:]')
if [ "${ANA_EXISTS:-0}" -eq 0 ]; then
    echo "WARNING: Ana Betz not found in demo database. Demo DB may not have been restored correctly."
fi
echo "Ana Betz patient found: $ANA_EXISTS"

# 4. Ensure GNU Health server is running
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

# 5. Ensure logged in and navigate to GNU Health
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# 6. Take initial screenshot
take_screenshot /tmp/schedule_appointment_initial.png

echo "=== schedule_appointment task setup complete ==="
echo "Task: Schedule appointment for Ana Betz on 2027-03-15 at 09:30"
echo "Navigate to Appointment module, click New, fill in patient, date, time and notes"
