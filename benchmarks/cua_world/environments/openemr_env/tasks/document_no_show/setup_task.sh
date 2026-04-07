#!/bin/bash
# Setup script for Document No-Show Task
# Creates an appointment for today at 9:00 AM that the agent must mark as no-show

echo "=== Setting up Document No-Show Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Target patient: Mariana Altenwerth (pid=2)
PATIENT_PID=2
PATIENT_NAME="Mariana Altenwerth"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    echo "Checking available patients..."
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Get today's date in MySQL format
TODAY=$(date +%Y-%m-%d)
echo "Today's date: $TODAY"

# Clean up any existing test appointments for today
echo "Cleaning up existing appointments for patient on $TODAY..."
openemr_query "DELETE FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate='$TODAY' AND pc_startTime='09:00:00'" 2>/dev/null || true

# Create the appointment for today at 9:00 AM
# Status '-' means scheduled/pending (not no-show)
echo "Creating appointment for $PATIENT_NAME at 9:00 AM..."
openemr_query "INSERT INTO openemr_postcalendar_events 
(pc_catid, pc_pid, pc_title, pc_eventDate, pc_startTime, pc_endTime, 
 pc_duration, pc_apptstatus, pc_hometext, pc_aid, pc_facility, pc_informant)
VALUES 
(5, $PATIENT_PID, 'Office Visit', '$TODAY', '09:00:00', '09:30:00', 
 1800, '-', '', 1, 3, 'admin')" 2>/dev/null

# Verify appointment was created
echo "Verifying appointment creation..."
APPT_CHECK=$(openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_apptstatus FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate='$TODAY' AND pc_startTime='09:00:00'" 2>/dev/null)
if [ -z "$APPT_CHECK" ]; then
    echo "ERROR: Failed to create appointment!"
    exit 1
fi
echo "Appointment created: $APPT_CHECK"

# Record initial appointment state for verification comparison
echo "$APPT_CHECK" > /tmp/initial_appointment_state.txt
INITIAL_EID=$(echo "$APPT_CHECK" | cut -f1)
INITIAL_STATUS=$(echo "$APPT_CHECK" | cut -f5)
echo "$INITIAL_EID" > /tmp/initial_appointment_eid.txt
echo "$INITIAL_STATUS" > /tmp/initial_appointment_status.txt
echo "Initial EID: $INITIAL_EID, Status: '$INITIAL_STATUS'"

# Record the appointment count for this patient
APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$APPT_COUNT" > /tmp/initial_appt_count.txt
echo "Total appointments for patient: $APPT_COUNT"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox for clean start
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved"

echo ""
echo "=== Document No-Show Task Setup Complete ==="
echo ""
echo "TASK DETAILS:"
echo "============="
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1969-02-22)"
echo "Appointment: Today ($TODAY) at 9:00 AM"
echo "Current Status: Scheduled (pending)"
echo ""
echo "YOUR TASK:"
echo "1. Log in to OpenEMR (admin/pass)"
echo "2. Navigate to Calendar"
echo "3. Find the 9:00 AM appointment for Mariana Altenwerth"
echo "4. Change status to 'No Show'"
echo "5. Add comment about contact attempts"
echo "6. Save changes"
echo ""