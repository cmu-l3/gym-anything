#!/bin/bash
# Setup script for Close Patient Encounter Task

echo "=== Setting up Close Patient Encounter Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient and encounter details
PATIENT_PID=6
PATIENT_NAME="Elena Schroeder"
ENCOUNTER_DATE="2019-10-15"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify encounter exists for this patient
echo "Verifying encounter exists for date $ENCOUNTER_DATE..."
ENCOUNTER_CHECK=$(openemr_query "SELECT id, date, reason, last_level_closed FROM form_encounter WHERE pid=$PATIENT_PID AND DATE(date)='$ENCOUNTER_DATE' LIMIT 1" 2>/dev/null)
if [ -z "$ENCOUNTER_CHECK" ]; then
    echo "ERROR: Encounter not found for patient on $ENCOUNTER_DATE!"
    exit 1
fi
echo "Encounter found: $ENCOUNTER_CHECK"

# CRITICAL: Reset the encounter to OPEN state (ensure it's not already closed)
echo "Resetting encounter to OPEN state for task..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
    UPDATE form_encounter 
    SET last_level_closed = 0, last_level_billed = 0
    WHERE pid = $PATIENT_PID AND DATE(date) = '$ENCOUNTER_DATE';
" 2>/dev/null

# Verify reset was successful
CLOSED_STATUS=$(openemr_query "SELECT last_level_closed FROM form_encounter WHERE pid=$PATIENT_PID AND DATE(date)='$ENCOUNTER_DATE' LIMIT 1" 2>/dev/null)
echo "Encounter closed status after reset: $CLOSED_STATUS (should be 0)"

# Record initial encounter state for verification
INITIAL_ENCOUNTER_STATE=$(openemr_query "SELECT id, last_level_closed, last_level_billed FROM form_encounter WHERE pid=$PATIENT_PID AND DATE(date)='$ENCOUNTER_DATE' LIMIT 1" 2>/dev/null)
echo "$INITIAL_ENCOUNTER_STATE" > /tmp/initial_encounter_state.txt
echo "Initial encounter state saved: $INITIAL_ENCOUNTER_STATE"

# Get encounter ID for later verification
ENCOUNTER_ID=$(openemr_query "SELECT id FROM form_encounter WHERE pid=$PATIENT_PID AND DATE(date)='$ENCOUNTER_DATE' LIMIT 1" 2>/dev/null)
echo "$ENCOUNTER_ID" > /tmp/target_encounter_id.txt
echo "Target encounter ID: $ENCOUNTER_ID"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox to ensure clean state
pkill firefox 2>/dev/null || true
sleep 2

# Start Firefox fresh
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
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Close Patient Encounter Task Setup Complete ==="
echo ""
echo "TASK SUMMARY:"
echo "  Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "  DOB: 1984-05-21"
echo "  Encounter Date: $ENCOUNTER_DATE"
echo "  Encounter ID: $ENCOUNTER_ID"
echo "  Current Status: OPEN (last_level_closed = 0)"
echo ""
echo "OBJECTIVE: Navigate to this encounter and close/finalize it"
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""