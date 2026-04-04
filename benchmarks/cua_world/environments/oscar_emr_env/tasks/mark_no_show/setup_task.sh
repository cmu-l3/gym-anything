#!/bin/bash
set -e
echo "=== Setting up Mark No-Show task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OSCAR is running
wait_for_oscar_http 180

TODAY=$(date +%Y-%m-%d)
echo "Today is $TODAY"

# ============================================================
# 1. Create patient Robert Thornton if not exists
# ============================================================
echo "Creating patient Robert Thornton..."
PATIENT_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Robert' AND last_name='Thornton'" | tr -d '[:space:]')

if [ "${PATIENT_EXISTS:-0}" -eq 0 ]; then
    oscar_query "INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth, year_of_birth, month_of_birth,
        hin, ver, province, address, city, postal,
        phone, patient_status, date_joined, chart_no,
        provider_no, family_doctor
    ) VALUES (
        'Thornton', 'Robert', 'M', '1978-06-22', '1978', '06',
        '6822451789', 'AB', 'ON', '47 Lakeview Drive', 'Toronto', 'M5V2T6',
        '416-555-0198', 'AC', '$TODAY', '90210',
        '999998', '<rdohid>999998</rdohid><rd>Dr. Sarah Chen</rd>'
    );"
    echo "Patient Robert Thornton created."
else
    echo "Patient Robert Thornton already exists."
fi

# Get patient demographic_no
DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Robert' AND last_name='Thornton' ORDER BY demographic_no DESC LIMIT 1" | tr -d '[:space:]')
echo "Robert Thornton demographic_no: $DEMO_NO"
echo "$DEMO_NO" > /tmp/noshow_demo_no.txt

# ============================================================
# 2. Ensure schedule template exists for provider 999998 today
# ============================================================
echo "Setting up schedule template for today..."
# Template timecode: 1 char per 15-min slot from 08:00 to 17:00
TEMPLATE_CODE="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

# Check/Create template
TEMPLATE_EXISTS=$(oscar_query "SELECT COUNT(*) FROM scheduletemplate WHERE name='PublicNoShow' AND provider_no='999998'" | tr -d '[:space:]')
if [ "${TEMPLATE_EXISTS:-0}" -eq 0 ]; then
    oscar_query "INSERT INTO scheduletemplate (name, timecode, provider_no, summary)
        VALUES ('PublicNoShow', '${TEMPLATE_CODE}', '999998', 'Full Day Schedule');" 2>/dev/null || true
fi

# Set today's schedule to use this template
SCHED_DATE_EXISTS=$(oscar_query "SELECT COUNT(*) FROM scheduledate WHERE sdate='$TODAY' AND provider_no='999998'" | tr -d '[:space:]')
if [ "${SCHED_DATE_EXISTS:-0}" -eq 0 ]; then
    oscar_query "INSERT INTO scheduledate (sdate, provider_no, available, priority, hour)
        VALUES ('$TODAY', '999998', 'A', 'a', 'PublicNoShow');" 2>/dev/null || true
fi

# ============================================================
# 3. Create the appointment for Robert Thornton at 10:00 AM
# ============================================================
echo "Creating 10:00 AM appointment for Robert Thornton..."

# Remove any existing test appointments for this patient today
oscar_query "DELETE FROM appointment WHERE demographic_no=${DEMO_NO} AND appointment_date='$TODAY' AND start_time='10:00:00';" 2>/dev/null || true

# Insert fresh appointment with status 't' (Active/Scheduled)
oscar_query "INSERT INTO appointment (
    provider_no, appointment_date, start_time, end_time,
    name, demographic_no, status, reason, notes, type,
    location, creator, lastUpdateUser, createdatetime, updatedatetime
) VALUES (
    '999998', '$TODAY', '10:00:00', '10:15:00',
    'Thornton, Robert', ${DEMO_NO}, 't', 'Follow-up visit', '', '',
    '', 'oscardoc', 'oscardoc', NOW(), NOW()
);"

# Get appointment_no for verification
APPT_NO=$(oscar_query "SELECT appointment_no FROM appointment WHERE demographic_no=${DEMO_NO} AND appointment_date='$TODAY' AND start_time='10:00:00' ORDER BY appointment_no DESC LIMIT 1" | tr -d '[:space:]')
echo "$APPT_NO" > /tmp/noshow_appt_no.txt

# Record initial status
INITIAL_STATUS=$(oscar_query "SELECT status FROM appointment WHERE appointment_no=${APPT_NO}" | tr -d '[:space:]')
echo "$INITIAL_STATUS" > /tmp/noshow_initial_status.txt

# ============================================================
# 4. Launch Firefox on Oscar login
# ============================================================
echo "Launching Firefox..."
ensure_firefox_on_oscar

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Patient ID: $DEMO_NO"
echo "Appointment ID: $APPT_NO"
echo "Initial Status: $INITIAL_STATUS"