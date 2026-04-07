#!/bin/bash
# Setup script for Reschedule Appointment task
# Creates an initial appointment that the agent must reschedule

echo "=== Setting up Reschedule Appointment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
TASK_DATE=$(date +%Y-%m-%d)
echo "$TASK_DATE" > /tmp/task_start_date.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"
echo "Task start date: $TASK_DATE"

# Calculate dates
TOMORROW=$(date -d "+1 day" +%Y-%m-%d)
DAY_AFTER=$(date -d "+2 days" +%Y-%m-%d)
echo "$TOMORROW" > /tmp/original_appt_date.txt
echo "$DAY_AFTER" > /tmp/target_appt_date.txt
echo "Original appointment date: $TOMORROW"
echo "Target reschedule date: $DAY_AFTER"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Clean up any existing test appointments for this patient in the date range
echo "Cleaning up existing appointments for patient $PATIENT_PID in test date range..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
DELETE FROM openemr_postcalendar_events 
WHERE pc_pid = $PATIENT_PID 
  AND pc_eventDate >= CURDATE()
  AND pc_eventDate <= DATE_ADD(CURDATE(), INTERVAL 7 DAY);
" 2>/dev/null || true

# Record initial state (should be 0 appointments in date range after cleanup)
INITIAL_APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate >= CURDATE() AND pc_eventDate <= DATE_ADD(CURDATE(), INTERVAL 7 DAY)" 2>/dev/null || echo "0")
echo "$INITIAL_APPT_COUNT" > /tmp/initial_appt_count.txt
echo "Initial appointment count in date range: $INITIAL_APPT_COUNT"

# Create the appointment to be rescheduled (tomorrow at 10:00 AM)
echo "Creating appointment for tomorrow ($TOMORROW) at 10:00 AM..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
INSERT INTO openemr_postcalendar_events 
(pc_catid, pc_aid, pc_pid, pc_title, pc_time, pc_eventDate, 
 pc_startTime, pc_endTime, pc_duration, pc_recurrtype, pc_recurrfreq,
 pc_eventstatus, pc_sharing, pc_apptstatus, pc_facility, pc_billing_location,
 pc_hometext)
VALUES 
(5, 1, $PATIENT_PID, 'Office Visit', NOW(), 
 '$TOMORROW', 
 '10:00:00', '10:30:00', 1800, 0, 0, 1, 1, '-', 3, 3,
 'Regular office visit');
"

# Verify appointment was created and get its ID
APPT_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "
SELECT pc_eid FROM openemr_postcalendar_events 
WHERE pc_pid = $PATIENT_PID 
  AND pc_eventDate = '$TOMORROW'
  AND pc_startTime = '10:00:00'
ORDER BY pc_eid DESC LIMIT 1;
" 2>/dev/null)

if [ -z "$APPT_ID" ]; then
    echo "ERROR: Failed to create initial appointment!"
    exit 1
fi

echo "$APPT_ID" > /tmp/original_appt_id.txt
echo "Created appointment ID: $APPT_ID"

# Verify appointment details
echo ""
echo "=== Initial Appointment Details ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_title
FROM openemr_postcalendar_events 
WHERE pc_eid = $APPT_ID;
" 2>/dev/null

# Count appointments after setup
SETUP_APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate >= CURDATE() AND pc_eventDate <= DATE_ADD(CURDATE(), INTERVAL 7 DAY)" 2>/dev/null || echo "0")
echo "$SETUP_APPT_COUNT" > /tmp/setup_appt_count.txt
echo "Appointment count after setup: $SETUP_APPT_COUNT"

# Ensure Firefox is running on OpenEMR login page
echo ""
echo "Setting up Firefox..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox for clean start
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png

echo ""
echo "=== Reschedule Appointment Task Setup Complete ==="
echo ""
echo "TASK SUMMARY:"
echo "============="
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo ""
echo "Current Appointment:"
echo "  - Date: $TOMORROW (tomorrow)"
echo "  - Time: 10:00 AM"
echo "  - Duration: 30 minutes"
echo "  - Type: Office Visit"
echo ""
echo "Reschedule To:"
echo "  - Date: $DAY_AFTER (day after tomorrow)"
echo "  - Time: 2:30 PM"
echo ""
echo "Login: admin / pass"
echo ""