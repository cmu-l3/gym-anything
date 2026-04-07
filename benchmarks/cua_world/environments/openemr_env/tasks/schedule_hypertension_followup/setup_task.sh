#!/bin/bash
# Setup script for Schedule Hypertension Follow-up Task

echo "=== Setting up Schedule Hypertension Follow-up Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Verify patient exists and has hypertension
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify hypertension condition exists
echo "Verifying hypertension diagnosis..."
HTN_CHECK=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%Hypertension%' OR diagnosis LIKE '%59621000%')" 2>/dev/null)
if [ -z "$HTN_CHECK" ]; then
    echo "WARNING: Hypertension diagnosis not found for patient"
else
    echo "Hypertension confirmed: $HTN_CHECK"
fi

# Record initial appointment count for this patient
echo "Recording initial appointment count..."
INITIAL_APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_APPT_COUNT" > /tmp/initial_appt_count
echo "Initial appointment count for patient: $INITIAL_APPT_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

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

# Take initial screenshot for audit verification
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved to /tmp/task_start_screenshot.png"

echo ""
echo "=== Schedule Hypertension Follow-up Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Condition: Hypertension (requires follow-up appointment)"
echo ""
