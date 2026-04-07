#!/bin/bash
# Setup script for Create Recurring Appointment Series Task

echo "=== Setting up Create Recurring Appointment Series Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=1
PATIENT_NAME="Nereida Windler"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial appointment count for this patient
echo "Recording initial appointment count for patient..."
INITIAL_APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_APPT_COUNT" > /tmp/initial_appt_count.txt
echo "Initial appointment count for patient $PATIENT_PID: $INITIAL_APPT_COUNT"

# Record IDs of existing appointments (to distinguish new from old)
echo "Recording existing appointment IDs..."
EXISTING_IDS=$(openemr_query "SELECT pc_eid FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID ORDER BY pc_eid" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "$EXISTING_IDS" > /tmp/existing_appt_ids.txt
echo "Existing appointment IDs: $EXISTING_IDS"

# Calculate next Tuesday for reference
NEXT_TUESDAY=$(date -d "next Tuesday" +%Y-%m-%d)
echo "Next Tuesday: $NEXT_TUESDAY"
echo "$NEXT_TUESDAY" > /tmp/next_tuesday.txt

# Ensure Firefox is running on OpenEMR
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Create Recurring Appointment Series Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "DOB: 1959-06-07"
echo ""
echo "Task: Create 4 weekly Physical Therapy appointments"
echo "  - Day: Tuesdays (starting $NEXT_TUESDAY)"
echo "  - Time: 10:00 AM"
echo "  - Duration: 45 minutes"
echo "  - Reason: Physical Therapy - Post-op Knee Rehab"
echo ""
echo "Login credentials: admin / pass"
echo ""