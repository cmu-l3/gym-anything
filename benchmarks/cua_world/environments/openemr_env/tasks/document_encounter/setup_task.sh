#!/bin/bash
# Setup script for Document Encounter Task

echo "=== Setting up Document Encounter Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=9
PATIENT_NAME="Karyn Metz"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial encounter count for this patient
echo "Recording initial encounter count..."
INITIAL_ENC_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENC_COUNT" > /tmp/initial_enc_count
echo "Initial encounter count for patient: $INITIAL_ENC_COUNT"

# Record initial vitals count
INITIAL_VITALS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_vitals WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_VITALS_COUNT" > /tmp/initial_vitals_count
echo "Initial vitals count for patient: $INITIAL_VITALS_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
date +%Y-%m-%d > /tmp/task_start_date
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"
echo "Task start date: $(cat /tmp/task_start_date)"

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
echo "=== Document Encounter Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Task: Create encounter, document vitals, add URI diagnosis"
echo ""
