#!/bin/bash
# Setup script for check_in_appointment task
# Creates an appointment for today and ensures browser is ready

echo "=== Setting up Check-In Appointment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start time: $TASK_START"

# Patient info (Jayson Fadel from Synthea data)
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Get today's date in MySQL format
TODAY=$(date +%Y-%m-%d)
APPT_TIME="10:30:00"
APPT_END_TIME="11:00:00"

echo "Setting up appointment for ${PATIENT_NAME} (pid: ${PATIENT_PID}) on ${TODAY}"

# Verify patient exists
echo "Verifying patient exists..."
PATIENT_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT pid, fname, lname FROM patient_data WHERE pid=${PATIENT_PID}" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Check if appointment already exists for today
echo "Checking for existing appointment..."
EXISTING_APPT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT pc_eid FROM openemr_postcalendar_events WHERE pc_pid=${PATIENT_PID} AND pc_eventDate='${TODAY}' LIMIT 1" 2>/dev/null)

if [ -n "$EXISTING_APPT" ]; then
    echo "Appointment exists (eid: ${EXISTING_APPT}), resetting status to scheduled (blank)"
    # Reset status to blank (scheduled, not arrived)
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "UPDATE openemr_postcalendar_events SET pc_apptstatus='' WHERE pc_eid=${EXISTING_APPT}" 2>/dev/null
    APPT_EID=$EXISTING_APPT
else
    echo "Creating new appointment for today..."
    # Create appointment for today
    # Category 5 is typically "Office Visit", aid=1 is admin provider, facility=3
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "INSERT INTO openemr_postcalendar_events (
        pc_catid, pc_pid, pc_title, pc_time, pc_eventDate, 
        pc_startTime, pc_endTime, pc_duration, pc_hometext, 
        pc_apptstatus, pc_aid, pc_facility
    ) VALUES (
        5, ${PATIENT_PID}, 'Office Visit', NOW(), '${TODAY}',
        '${APPT_TIME}', '${APPT_END_TIME}', 1800, 'Routine follow-up visit',
        '', 1, 3
    )" 2>/dev/null
    
    # Get the created appointment ID
    APPT_EID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT pc_eid FROM openemr_postcalendar_events WHERE pc_pid=${PATIENT_PID} AND pc_eventDate='${TODAY}' ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)
fi

echo "Appointment EID: ${APPT_EID}"
echo "$APPT_EID" > /tmp/appointment_eid.txt

# Record initial status (should be blank = scheduled)
INITIAL_STATUS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT IFNULL(NULLIF(pc_apptstatus, ''), 'BLANK') FROM openemr_postcalendar_events WHERE pc_eid=${APPT_EID}" 2>/dev/null)
echo "$INITIAL_STATUS" > /tmp/initial_appointment_status.txt
echo "Initial appointment status: '${INITIAL_STATUS}'"

# Verify the appointment setup
echo ""
echo "=== Appointment Details ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_apptstatus, pc_title FROM openemr_postcalendar_events WHERE pc_eid=${APPT_EID}" 2>/dev/null

# Ensure Firefox is running on OpenEMR login page
echo ""
echo "Setting up browser..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill any existing Firefox to start fresh
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openemr"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Maximize and focus Firefox
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Found Firefox window: $WID"
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take screenshot of initial state
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Check In Patient for Scheduled Appointment"
echo "================================================"
echo ""
echo "Patient: ${PATIENT_NAME} (PID: ${PATIENT_PID})"
echo "DOB: 1992-06-30"
echo "Appointment Date: ${TODAY}"
echo "Appointment Time: ${APPT_TIME}"
echo "Current Status: SCHEDULED (blank)"
echo ""
echo "Instructions:"
echo "1. Log in to OpenEMR (admin/pass)"
echo "2. Navigate to Calendar"
echo "3. Find today's appointment for Jayson Fadel"
echo "4. Click on the appointment"
echo "5. Change status to 'Arrived' (@)"
echo "6. Save changes"
echo ""