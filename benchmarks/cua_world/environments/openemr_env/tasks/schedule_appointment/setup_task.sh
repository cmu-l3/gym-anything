#!/bin/bash
# Setup script for Schedule Appointment task

echo "=== Setting up Schedule Appointment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=2
PATIENT_NAME="Maria Espinal"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    echo "Attempting to check all patients..."
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial appointment count for this patient (for anti-gaming)
echo "Recording initial appointment count..."
INITIAL_APT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_APT_COUNT" > /tmp/initial_apt_count.txt
echo "Initial appointment count for Maria Espinal: $INITIAL_APT_COUNT"

# Also record total appointments to detect any appointment creation
INITIAL_TOTAL_APT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events" 2>/dev/null || echo "0")
echo "$INITIAL_TOTAL_APT" > /tmp/initial_total_apt_count.txt
echo "Initial total appointment count: $INITIAL_TOTAL_APT"

# Get the highest appointment ID (to detect new appointments)
MAX_APT_ID=$(openemr_query "SELECT COALESCE(MAX(pc_eid), 0) FROM openemr_postcalendar_events" 2>/dev/null || echo "0")
echo "$MAX_APT_ID" > /tmp/max_apt_id.txt
echo "Max appointment ID before task: $MAX_APT_ID"

# Calculate valid date range
TODAY=$(date +%Y-%m-%d)
MAX_DATE=$(date -d "+7 days" +%Y-%m-%d)
echo "Valid appointment date range: $TODAY to $MAX_DATE"
echo "$TODAY" > /tmp/valid_date_start.txt
echo "$MAX_DATE" > /tmp/valid_date_end.txt

# Ensure Firefox is running and focused on OpenEMR
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

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Schedule Appointment Task Setup Complete ==="
echo ""
echo "Task: Schedule an appointment for Maria Espinal"
echo ""
echo "Patient Details:"
echo "  - Name: Maria Espinal"
echo "  - DOB: 1964-08-17"
echo "  - Patient ID: 2"
echo ""
echo "Appointment Requirements:"
echo "  - Date: Within next 7 days ($TODAY to $MAX_DATE)"
echo "  - Time: 9:00 AM - 4:00 PM"
echo "  - Duration: 15 minutes"
echo "  - Type: Office Visit"
echo "  - Comment: 'Routine follow-up visit'"
echo ""