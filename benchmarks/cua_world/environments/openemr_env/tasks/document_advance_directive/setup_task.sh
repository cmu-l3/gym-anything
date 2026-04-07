#!/bin/bash
# Setup script for Document Advance Directive task

echo "=== Setting up Document Advance Directive Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=5
PATIENT_NAME="Jenna Ledner"

# Record task start timestamp for anti-gaming verification
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

# Record initial state of advance directive fields for this patient
echo "Recording initial advance directive state..."

# Get current ad_reviewed date
INITIAL_AD_REVIEWED=$(openemr_query "SELECT IFNULL(ad_reviewed, '') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "")
echo "$INITIAL_AD_REVIEWED" > /tmp/initial_ad_reviewed.txt
echo "Initial ad_reviewed: '$INITIAL_AD_REVIEWED'"

# Get current usertext fields (commonly used for AD info)
INITIAL_USERTEXTS=$(openemr_query "SELECT IFNULL(usertext1,''), IFNULL(usertext2,''), IFNULL(usertext3,''), IFNULL(usertext4,'') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "")
echo "$INITIAL_USERTEXTS" > /tmp/initial_usertexts.txt
echo "Initial usertext fields recorded"

# Record initial pnotes count for this patient
INITIAL_NOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_NOTES_COUNT" > /tmp/initial_notes_count.txt
echo "Initial notes count: $INITIAL_NOTES_COUNT"

# Record initial history_data state
INITIAL_HISTORY=$(openemr_query "SELECT COUNT(*) FROM history_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_HISTORY" > /tmp/initial_history_count.txt
echo "Initial history records: $INITIAL_HISTORY"

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

# Take initial screenshot for audit trail
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Document Advance Directive Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1941-10-06)"
echo "Age: 83 years (elderly patient - advance directive documentation critical)"
echo ""
echo "Task: Document that patient has advance directives on file:"
echo "  - Healthcare Proxy: Margaret Ledner (daughter)"
echo "  - Phone: (555) 123-4567"
echo "  - Documents: Healthcare Proxy, MOLST"
echo "  - MOLST indicates: DNR/DNI, comfort measures only"
echo ""
echo "Login: admin / pass"
echo ""