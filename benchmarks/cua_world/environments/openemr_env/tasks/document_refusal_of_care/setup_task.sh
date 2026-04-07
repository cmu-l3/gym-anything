#!/bin/bash
# Setup script for Document Refusal of Care task

echo "=== Setting up Document Refusal of Care task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Target patient details
PATIENT_FNAME="Rosario"
PATIENT_LNAME="Conn"

# Verify OpenEMR containers are running
echo "Checking OpenEMR services..."
if ! docker ps | grep -q openemr; then
    echo "ERROR: OpenEMR containers not running!"
    exit 1
fi
echo "OpenEMR containers are running"

# Verify patient exists in database
echo "Verifying patient $PATIENT_FNAME $PATIENT_LNAME exists..."
PATIENT_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname, DOB FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient $PATIENT_FNAME $PATIENT_LNAME not found in database!"
    echo "Checking available patients..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi

echo "Patient found: $PATIENT_CHECK"

# Extract and save patient PID for verification
PATIENT_PID=$(echo "$PATIENT_CHECK" | awk '{print $1}')
echo "$PATIENT_PID" > /tmp/target_patient_pid.txt
echo "Target patient PID: $PATIENT_PID"

# Record initial note count for this patient (for anti-gaming)
INITIAL_NOTE_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID AND activity=1" 2>/dev/null || echo "0")
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_note_count.txt
echo "Initial note count for patient: $INITIAL_NOTE_COUNT"

# Also record total pnotes count
TOTAL_INITIAL_NOTES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM pnotes WHERE activity=1" 2>/dev/null || echo "0")
echo "$TOTAL_INITIAL_NOTES" > /tmp/total_initial_notes.txt
echo "Total initial notes in system: $TOTAL_INITIAL_NOTES"

# Ensure Firefox is running and showing login page
echo "Setting up Firefox..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox to ensure clean state
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox with OpenEMR login page
echo "Starting Firefox with OpenEMR login page..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openemr"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
echo "Configuring Firefox window..."
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox window maximized: $WID"
else
    echo "WARNING: Could not find Firefox window ID"
fi

# Wait for page to fully load
sleep 3

# Dismiss any popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Document Refusal of Care Task Setup Complete ==="
echo ""
echo "TASK: Document Refusal of Care"
echo "==============================="
echo ""
echo "Clinical Scenario:"
echo "  Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "  DOB: 2005-09-19 (minor patient)"
echo "  Situation: Parent refused recommended MRI imaging"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin / pass)"
echo "  2. Search for and open patient '$PATIENT_FNAME $PATIENT_LNAME'"
echo "  3. Create a patient note documenting:"
echo "     - Title: Include 'Refusal' or 'AMA' or 'Declined'"
echo "     - Body: What was refused (MRI/imaging)"
echo "     - Body: That risks were explained to parent/guardian"
echo "  4. Save the note"
echo ""