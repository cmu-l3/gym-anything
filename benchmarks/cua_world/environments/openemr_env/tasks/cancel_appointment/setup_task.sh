#!/bin/bash
# Setup script for Cancel Appointment task

echo "=== Setting up Cancel Appointment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Configuration
PATIENT_FNAME="Sarah"
PATIENT_LNAME="Borer"
APPT_DATE="2024-12-20"
APPT_TIME="10:00:00"
APPT_END_TIME="10:30:00"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Find Sarah Borer's patient ID
echo "Looking for patient $PATIENT_FNAME $PATIENT_LNAME..."
SARAH_PID=$(openemr_query "SELECT pid FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)

if [ -z "$SARAH_PID" ]; then
    echo "ERROR: Patient $PATIENT_FNAME $PATIENT_LNAME not found in database"
    echo "Checking available patients..."
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10"
    exit 1
fi

echo "Found patient $PATIENT_FNAME $PATIENT_LNAME with pid: $SARAH_PID"
echo "$SARAH_PID" > /tmp/task_patient_pid.txt

# Delete any existing test appointment for this date/time to ensure clean state
echo "Cleaning up any existing test appointments..."
openemr_query "DELETE FROM openemr_postcalendar_events WHERE pc_pid=$SARAH_PID AND pc_eventDate='$APPT_DATE' AND pc_startTime='$APPT_TIME'" 2>/dev/null || true

# Create the appointment to be cancelled
echo "Creating test appointment for December 20, 2024 at 10:00 AM..."
openemr_query "INSERT INTO openemr_postcalendar_events (pc_catid, pc_pid, pc_title, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_hometext, pc_apptstatus, pc_aid, pc_time) VALUES (5, $SARAH_PID, 'Office Visit', '$APPT_DATE', '$APPT_TIME', '$APPT_END_TIME', 1800, 'Regular checkup', '-', 1, NOW())"

# Get the appointment ID for verification
APPT_ID=$(openemr_query "SELECT pc_eid FROM openemr_postcalendar_events WHERE pc_pid=$SARAH_PID AND pc_eventDate='$APPT_DATE' AND pc_startTime='$APPT_TIME' ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)

if [ -z "$APPT_ID" ]; then
    echo "ERROR: Failed to create test appointment"
    exit 1
fi

echo "Created appointment with pc_eid: $APPT_ID"
echo "$APPT_ID" > /tmp/task_appointment_id.txt

# Record initial appointment status
INITIAL_STATUS=$(openemr_query "SELECT pc_apptstatus FROM openemr_postcalendar_events WHERE pc_eid=$APPT_ID" 2>/dev/null)
echo "$INITIAL_STATUS" > /tmp/task_initial_status.txt
echo "Initial appointment status: '$INITIAL_STATUS'"

# Verify the appointment was created correctly
echo ""
echo "=== Verifying appointment creation ==="
openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_apptstatus, pc_hometext FROM openemr_postcalendar_events WHERE pc_eid=$APPT_ID" 2>/dev/null

# Record initial appointment count for this patient
INITIAL_APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$SARAH_PID" 2>/dev/null || echo "0")
echo "$INITIAL_APPT_COUNT" > /tmp/task_initial_appt_count.txt
echo "Initial appointment count for patient: $INITIAL_APPT_COUNT"

# Ensure Firefox is running and focused on OpenEMR
echo ""
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
take_screenshot /tmp/task_initial_state.png

echo ""
echo "=== Cancel Appointment Task Setup Complete ==="
echo ""
echo "Task: Cancel an appointment"
echo "=============================================="
echo ""
echo "Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $SARAH_PID)"
echo "Appointment: $APPT_DATE at 10:00 AM (EID: $APPT_ID)"
echo "Current Status: '$INITIAL_STATUS' (Scheduled)"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin/pass)"
echo "  2. Navigate to Calendar"
echo "  3. Find appointment on December 20, 2024 at 10:00 AM"
echo "  4. Change status to 'Cancelled'"
echo "  5. Add reason: 'Patient requested cancellation - work conflict'"
echo "  6. Save changes (do NOT delete the appointment)"
echo ""