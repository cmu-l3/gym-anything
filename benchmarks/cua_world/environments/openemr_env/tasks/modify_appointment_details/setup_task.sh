#!/bin/bash
# Setup script for Modify Appointment Details task
# Creates an initial appointment that the agent must modify

echo "=== Setting up Modify Appointment Details Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Patient details
PATIENT_PID=2
PATIENT_NAME="Marilynn Corkery"

# Calculate tomorrow's date for the appointment
TOMORROW=$(date -d "+1 day" +%Y-%m-%d)
echo "Appointment will be scheduled for: $TOMORROW at 10:00 AM"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)

if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Get Follow Up category ID from the database
echo "Finding Follow Up category ID..."
FOLLOWUP_CATID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pc_catid FROM openemr_postcalendar_categories WHERE pc_catname LIKE '%Follow%' LIMIT 1" 2>/dev/null)

# Default to category 9 if not found (common Follow Up category ID)
if [ -z "$FOLLOWUP_CATID" ] || [ "$FOLLOWUP_CATID" = "" ]; then
    FOLLOWUP_CATID="9"
    echo "Using default Follow Up category ID: $FOLLOWUP_CATID"
else
    echo "Found Follow Up category ID: $FOLLOWUP_CATID"
fi

# Get Office Visit category ID for reference
OFFICE_VISIT_CATID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pc_catid FROM openemr_postcalendar_categories WHERE pc_catname LIKE '%Office%Visit%' OR pc_catname = 'Office Visit' LIMIT 1" 2>/dev/null)
echo "Office Visit category ID (for reference): $OFFICE_VISIT_CATID"

# Delete any existing test appointments for this patient on tomorrow's date
echo "Cleaning up any existing appointments for tomorrow..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "DELETE FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate='$TOMORROW'" 2>/dev/null || true

# Create the initial 15-minute Follow Up appointment
echo "Creating initial 15-minute Follow Up appointment..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
    INSERT INTO openemr_postcalendar_events 
    (pc_catid, pc_multiple, pc_aid, pc_pid, pc_title, pc_time, pc_hometext,
     pc_eventDate, pc_endDate, pc_duration, pc_recurrtype, pc_recurrspec,
     pc_startTime, pc_endTime, pc_alldayevent, pc_apptstatus, pc_prefcatid,
     pc_location, pc_eventstatus, pc_sharing, pc_facility)
    VALUES 
    ($FOLLOWUP_CATID, 0, 1, $PATIENT_PID, 'Follow Up', NOW(), 'Medication follow-up',
     '$TOMORROW', '$TOMORROW', 900, 0, NULL,
     '10:00:00', '10:15:00', 0, '-', 0,
     '', 1, 1, 3)
" 2>/dev/null

# Verify appointment was created and get its ID
APPT_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pc_eid FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate='$TOMORROW' AND pc_startTime='10:00:00' ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)

if [ -z "$APPT_ID" ]; then
    echo "ERROR: Failed to create initial appointment!"
    exit 1
fi
echo "Created appointment with ID: $APPT_ID"

# Record initial appointment state for verification
echo "Recording initial appointment state..."
INITIAL_STATE=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pc_eid, pc_catid, pc_duration, pc_hometext, pc_eventDate, pc_startTime, pc_title 
     FROM openemr_postcalendar_events WHERE pc_eid=$APPT_ID" 2>/dev/null)

echo "$INITIAL_STATE" > /tmp/initial_appointment_state.txt
echo "Initial state recorded: $INITIAL_STATE"

# Save important values for verification
echo "$APPT_ID" > /tmp/original_appt_id.txt
echo "$TOMORROW" > /tmp/appointment_date.txt
echo "$FOLLOWUP_CATID" > /tmp/initial_catid.txt
echo "900" > /tmp/initial_duration.txt

# Parse and save individual initial values
INITIAL_CATID=$(echo "$INITIAL_STATE" | cut -f2)
INITIAL_DURATION=$(echo "$INITIAL_STATE" | cut -f3)
INITIAL_COMMENT=$(echo "$INITIAL_STATE" | cut -f4)
INITIAL_DATE=$(echo "$INITIAL_STATE" | cut -f5)
INITIAL_TIME=$(echo "$INITIAL_STATE" | cut -f6)

echo "Initial values:"
echo "  - Category ID: $INITIAL_CATID"
echo "  - Duration: $INITIAL_DURATION seconds ($(($INITIAL_DURATION / 60)) minutes)"
echo "  - Comment: $INITIAL_COMMENT"
echo "  - Date: $INITIAL_DATE"
echo "  - Time: $INITIAL_TIME"

# Kill any existing Firefox instances for clean start
echo "Preparing browser..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at OpenEMR login page
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"
echo "Starting Firefox at $OPENEMR_URL..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openemr"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
sleep 2
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox window focused and maximized: $WID"
fi

# Take initial screenshot for audit
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

echo ""
echo "=== Modify Appointment Details Task Setup Complete ==="
echo ""
echo "TASK INSTRUCTIONS:"
echo "=================="
echo ""
echo "Patient: $PATIENT_NAME (DOB: 1945-04-01)"
echo "Appointment Date: $TOMORROW at 10:00 AM"
echo ""
echo "Current appointment settings:"
echo "  - Duration: 15 minutes"
echo "  - Type: Follow Up"
echo "  - Comment: Medication follow-up"
echo ""
echo "MODIFY the appointment to:"
echo "  - Duration: 30 minutes"
echo "  - Type: Office Visit"
echo "  - Comment: Add 'Extended - patient has additional concerns'"
echo ""
echo "DO NOT change the appointment date or time!"
echo ""
echo "Login credentials: admin / pass"
echo ""