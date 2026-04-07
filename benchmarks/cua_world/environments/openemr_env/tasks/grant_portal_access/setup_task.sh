#!/bin/bash
# Setup script for Grant Patient Portal Access task

echo "=== Setting up Grant Patient Portal Access Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=2
PATIENT_NAME="Angila Fadel"

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

# Record initial portal status for this patient
echo "Recording initial portal status..."
INITIAL_PORTAL_STATUS=$(openemr_query "SELECT allow_patient_portal, portal_username FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "$INITIAL_PORTAL_STATUS" > /tmp/initial_portal_status.txt
echo "Initial portal status: $INITIAL_PORTAL_STATUS"

# Also record the patient's last modified timestamp
INITIAL_MODIFIED=$(openemr_query "SELECT DATE_FORMAT(date, '%Y-%m-%d %H:%i:%s') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "unknown")
echo "$INITIAL_MODIFIED" > /tmp/initial_patient_modified.txt
echo "Initial patient record timestamp: $INITIAL_MODIFIED"

# Ensure portal access is NOT already enabled (reset if needed for clean test)
echo "Ensuring portal access is disabled for clean test..."
openemr_query "UPDATE patient_data SET allow_patient_portal='', portal_username=NULL WHERE pid=$PATIENT_PID" 2>/dev/null || true

# Verify the reset worked
RESET_CHECK=$(openemr_query "SELECT allow_patient_portal, portal_username FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "After reset: $RESET_CHECK"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox to ensure clean start
pkill -f firefox 2>/dev/null || true
sleep 2

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
echo "=== Grant Patient Portal Access Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1990-01-18)"
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR (admin / pass)"
echo "  2. Find patient 'Angila Fadel'"
echo "  3. Go to Demographics and click Edit"
echo "  4. Find the 'Patient Portal' section"
echo "  5. Set 'Allow Patient Portal' to YES"
echo "  6. Set Portal Username to: angila.fadel"
echo "  7. Set Portal Password to: Portal2024!"
echo "  8. Save the changes"
echo ""