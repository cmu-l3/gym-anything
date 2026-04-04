#!/bin/bash
# Setup script for Schedule Recurring Appointment task in OSCAR EMR

echo "=== Setting up Schedule Recurring Appointment Task ==="

source /workspace/scripts/task_utils.sh

# 1. Verify/Create patient Michael Chang
# We use a specific DOB to ensure uniqueness if we need to recreate
FNAME="Michael"
LNAME="Chang"
DOB="1980-05-15"

echo "Ensuring patient $FNAME $LNAME exists..."
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$FNAME' AND last_name='$LNAME'" || echo "0")

if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "Creating patient $FNAME $LNAME..."
    # Insert patient with provider 999998 (oscardoc)
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('$LNAME', '$FNAME', 'M', '1980', '05', '15', 'Toronto', 'ON', 'M5V 2H1', '416-555-0199', '999998', '9876543210', 'ON', 'AC', NOW());" 2>/dev/null || true
fi

# Get demographic_no
PATIENT_ID=$(get_patient_id "$FNAME" "$LNAME")
echo "Patient ID: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/task_patient_id

# 2. Clear any existing future appointments for this patient to ensure clean verification
echo "Clearing existing future appointments for patient..."
oscar_query "DELETE FROM appointment WHERE demographic_no='$PATIENT_ID' AND appointment_date >= CURDATE()" 2>/dev/null || true

# 3. Calculate "First Tuesday after today"
# We use python for reliable date math
TARGET_DATE=$(python3 -c "
import datetime
today = datetime.date.today()
# Calculate days until next Tuesday (Tuesday is 1)
# If today is Tuesday (1), we want next Tuesday (so +7)
# If today is Monday (0), we want tomorrow (+1)
days_ahead = (1 - today.weekday() + 7) % 7
if days_ahead == 0:
    days_ahead = 7
target = today + datetime.timedelta(days=days_ahead)
print(target.strftime('%Y-%m-%d'))
")

echo "Calculated Start Date (Next Tuesday): $TARGET_DATE"
echo "$TARGET_DATE" > /tmp/task_target_date

# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox on Login Page
ensure_firefox_on_oscar

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Setup Complete ==="
echo "Task Configuration:"
echo "  Patient: $FNAME $LNAME (ID: $PATIENT_ID)"
echo "  Target Start Date: $TARGET_DATE"
echo "  Time: 10:00 AM"
echo "  Recurrence: 4 weeks"
echo ""