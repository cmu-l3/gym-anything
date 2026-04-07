#!/bin/bash
# Setup script for Record Telephone Encounter Task

echo "=== Setting up Record Telephone Encounter Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Record initial encounter count for this patient
echo "Recording initial encounter count for patient $PATIENT_NAME (pid=$PATIENT_PID)..."
INITIAL_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTER_COUNT" > /tmp/initial_encounter_count.txt
echo "Initial encounter count: $INITIAL_ENCOUNTER_COUNT"

# Record highest encounter ID for this patient (to detect new encounters)
HIGHEST_ENCOUNTER_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$HIGHEST_ENCOUNTER_ID" > /tmp/highest_encounter_id.txt
echo "Highest encounter ID: $HIGHEST_ENCOUNTER_ID"

# Verify patient exists
echo "Verifying patient exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient $PATIENT_NAME (pid=$PATIENT_PID) not found!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify patient has hypertension (for context)
echo "Verifying hypertension diagnosis..."
HTN_CHECK=$(openemr_query "SELECT title FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%Hypertension%' OR diagnosis LIKE '%59621000%')" 2>/dev/null)
if [ -n "$HTN_CHECK" ]; then
    echo "Hypertension confirmed: $HTN_CHECK"
else
    echo "Note: Hypertension diagnosis not found in problem list (may use different coding)"
fi

# Check available encounter categories (for debugging)
echo ""
echo "=== Available Encounter Categories ==="
openemr_query "SELECT pc_catid, pc_catname FROM openemr_postcalendar_categories WHERE pc_cattype IN (0,1,2,3) ORDER BY pc_catid LIMIT 20" 2>/dev/null || true
echo ""

# Ensure Firefox is running on OpenEMR login page
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

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial_state.png
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Record Telephone Encounter Task Setup Complete ==="
echo ""
echo "TASK: Document a telephone encounter for patient $PATIENT_NAME"
echo ""
echo "Patient called reporting dizziness symptoms possibly related to"
echo "blood pressure medication. You need to create a telephone encounter"
echo "to document this call."
echo ""
echo "Login credentials: admin / pass"
echo ""