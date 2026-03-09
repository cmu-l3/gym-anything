#!/bin/bash
set -e
echo "=== Setting up Reschedule Appointment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure OSCAR is running and accessible
# ============================================================
wait_for_oscar_http 300

# ============================================================
# 2. Ensure schedule templates exist for the target dates
#    Provider 999998 = Dr. Sarah Chen (oscardoc)
#    We need schedule coverage for July 15 and July 17, 2025
# ============================================================
echo "Setting up schedule templates for provider 999998..."

# Create a schedule template code 'A' (if not already existing)
# Template 'A' = standard clinic day
oscar_query "INSERT IGNORE INTO scheduletemplate (provider_no, name, timecode, summary)
VALUES ('999998', 'A',
'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
'Morning and Afternoon Clinic');"

# Assign the template to both target dates
oscar_query "INSERT IGNORE INTO scheduledate (provider_no, sdate, available, priority, reason, hour)
VALUES ('999998', '2025-07-15', 'A', '1', '', '');"

oscar_query "INSERT IGNORE INTO scheduledate (provider_no, sdate, available, priority, reason, hour)
VALUES ('999998', '2025-07-17', 'A', '1', '', '');"

# Also set templates for surrounding dates for realism
for d in 14 16 18; do
    oscar_query "INSERT IGNORE INTO scheduledate (provider_no, sdate, available, priority, reason, hour)
    VALUES ('999998', '2025-07-$d', 'A', '1', '', '');" 2>/dev/null || true
done

echo "Schedule templates configured."

# ============================================================
# 3. Ensure patient Maria Santos exists (demographic_no = 2)
# ============================================================
echo "Verifying patient Maria Santos..."
PATIENT_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE demographic_no=2;" || echo "0")

if [ "${PATIENT_EXISTS:-0}" -lt 1 ]; then
    echo "Patient demographic_no=2 not found, creating..."
    oscar_query "INSERT INTO demographic (demographic_no, last_name, first_name, sex, date_of_birth,
        hin, ver, roster_status, patient_status, date_joined, chart_no, province, pin,
        family_doctor, address, city, postal, phone)
    VALUES (2, 'Santos', 'Maria', 'F', '1975-08-22',
        '6789012345', 'AB', 'RO', 'AC', CURDATE(), '10002', 'ON', '',
        '<rdohip>999998</rdohip><rd>Dr. Sarah Chen</rd>',
        '456 Oak Avenue', 'Toronto', 'M5V 2T6', '416-555-0142');"
fi

# ============================================================
# 4. Create the initial appointment to be rescheduled
#    July 15, 2025 at 10:00 AM, reason: "Follow-up"
# ============================================================
echo "Creating initial appointment for Maria Santos on 2025-07-15 at 10:00..."

# First, remove any pre-existing appointments for this patient on these dates to ensure clean state
oscar_query "DELETE FROM appointment WHERE demographic_no=2 AND appointment_date IN ('2025-07-15', '2025-07-17');" 2>/dev/null || true

# Create the appointment to be rescheduled
# status='t' means Active/To Do
oscar_query "INSERT INTO appointment (provider_no, appointment_date, start_time, end_time,
    name, demographic_no, status, reason, notes, type, location, creator, lastupdateuser)
VALUES ('999998', '2025-07-15', '10:00:00', '10:15:00',
    'Santos,Maria', 2, 't', 'Follow-up', 'Regular follow-up visit', '',
    '', 'setup', 'setup');"

# Record initial state counts for verification
echo "Recording initial state..."
APPT_COUNT_JULY15=$(oscar_query "SELECT COUNT(*) FROM appointment WHERE demographic_no=2 AND appointment_date='2025-07-15' AND status='t';" || echo "0")
echo "$APPT_COUNT_JULY15" > /tmp/initial_july15_count.txt

APPT_COUNT_JULY17=$(oscar_query "SELECT COUNT(*) FROM appointment WHERE demographic_no=2 AND appointment_date='2025-07-17';" || echo "0")
echo "$APPT_COUNT_JULY17" > /tmp/initial_july17_count.txt

# ============================================================
# 5. Launch Firefox on OSCAR login page
# ============================================================
echo "Launching Firefox..."
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Reschedule Appointment Task Setup Complete ==="