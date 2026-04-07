#!/bin/bash
# Setup script for Document Surgical History Task
echo "=== Setting up Document Surgical History Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Record initial surgical history count for patient
echo "Recording initial surgical history count..."
INITIAL_SURGERY_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='surgery'" 2>/dev/null || echo "0")
echo "$INITIAL_SURGERY_COUNT" > /tmp/initial_surgery_count.txt
echo "Initial surgical history entries for patient $PATIENT_PID: $INITIAL_SURGERY_COUNT"

# Record all existing surgery IDs so we can identify new ones
docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id FROM lists WHERE pid=$PATIENT_PID AND type='surgery'" 2>/dev/null > /tmp/initial_surgery_ids.txt || true
echo "Existing surgery IDs recorded"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient $PATIENT_NAME (pid=$PATIENT_PID) not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Check if appendectomy already exists (for debugging)
EXISTING_APPENDECTOMY=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, title, begdate FROM lists WHERE pid=$PATIENT_PID AND type='surgery' AND LOWER(title) LIKE '%appendectomy%'" 2>/dev/null || echo "")
if [ -n "$EXISTING_APPENDECTOMY" ]; then
    echo "WARNING: Appendectomy already exists for this patient: $EXISTING_APPENDECTOMY"
    echo "Removing existing entry to ensure clean test state..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "DELETE FROM lists WHERE pid=$PATIENT_PID AND type='surgery' AND LOWER(title) LIKE '%appendectomy%'" 2>/dev/null || true
    # Update the count after removal
    INITIAL_SURGERY_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='surgery'" 2>/dev/null || echo "0")
    echo "$INITIAL_SURGERY_COUNT" > /tmp/initial_surgery_count.txt
fi

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
sleep 2
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Document Surgical History Task Setup Complete ==="
echo ""
echo "TASK: Document past surgical history for patient"
echo "=================================================="
echo ""
echo "Patient: $PATIENT_NAME (DOB: 1992-06-30)"
echo ""
echo "Surgical History to Add:"
echo "  - Procedure: Appendectomy"
echo "  - Date: 2015-03-22"
echo "  - Notes: Laparoscopic approach; uncomplicated recovery;"
echo "           performed at Springfield General Hospital"
echo ""
echo "Login credentials: admin / pass"
echo ""
echo "Navigate to patient's chart, find the Issues/Medical History"
echo "section, and add a new 'surgery' type entry."
echo ""