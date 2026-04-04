#!/bin/bash
# Setup script for Schedule Appointment task in OSCAR EMR

echo "=== Setting up Schedule Appointment Task ==="

source /workspace/scripts/task_utils.sh

# Verify patient Paul Tremblay exists (Synthea-generated patient)
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Paul' AND last_name='Tremblay'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "WARNING: Patient Paul Tremblay not found — seeding fallback record..."
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('Tremblay', 'Paul', 'M', '1954', '03', '15', 'Toronto', 'ON', 'M5V 1A1', '(416) 555-0432', '999998', '1234567890', 'ON', 'AC', NOW());" 2>/dev/null || true
fi
echo "Patient Paul Tremblay found."

PATIENT_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Paul' AND last_name='Tremblay' LIMIT 1")
echo "Patient demographic_no: $PATIENT_NO"

# Record timestamp for anti-gaming
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Record initial appointment count for this patient
INITIAL_APPT_COUNT=$(oscar_query "SELECT COUNT(*) FROM appointment WHERE demographic_no='$PATIENT_NO'" || echo "0")
echo "$INITIAL_APPT_COUNT" > /tmp/initial_appt_count
echo "Initial appointment count for Tremblay: $INITIAL_APPT_COUNT"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

# Compute next Monday's date for the task description
NEXT_MONDAY=$(date -d "next monday" +%Y-%m-%d 2>/dev/null || python3 -c "
from datetime import date, timedelta
today = date.today()
days_ahead = 7 - today.weekday() if today.weekday() != 0 else 7
print((today + timedelta(days=days_ahead)).strftime('%Y-%m-%d'))
")
echo "NEXT_MONDAY=$NEXT_MONDAY" > /tmp/task_date_info

echo ""
echo "=== Schedule Appointment Task Setup Complete ==="
echo ""
echo "TASK: Schedule an appointment for Paul Tremblay"
echo "  Patient:   Paul Tremblay (already registered)"
echo "  Date:      Next Monday ($NEXT_MONDAY)"
echo "  Time:      14:00 (2:00 PM)"
echo "  Provider:  Dr. Sarah Chen"
echo "  Reason:    Follow-up for blood pressure check"
echo ""
echo "Login: oscardoc / oscar / PIN: 1117"
echo ""
