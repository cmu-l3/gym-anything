#!/bin/bash
# Setup script for Mark Patient Inactive task

echo "=== Setting up Mark Patient Inactive Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient details
PATIENT_FNAME="Maria"
PATIENT_LNAME="Hickle"
PATIENT_DOB="1965-12-02"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_FNAME $PATIENT_LNAME exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB, active FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_CHECK" ]; then
    echo "WARNING: Patient $PATIENT_FNAME $PATIENT_LNAME not found in database"
    echo "Checking for similar patients..."
    openemr_query "SELECT pid, fname, lname FROM patient_data WHERE lname LIKE '%Hickle%' LIMIT 5" 2>/dev/null
else
    echo "Patient found: $PATIENT_CHECK"
fi

# Record initial patient status
echo "Recording initial patient status..."
INITIAL_STATUS=$(openemr_query "SELECT active FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null || echo "1")
echo "$INITIAL_STATUS" > /tmp/initial_patient_status.txt
echo "Initial active status: $INITIAL_STATUS"

# Record the patient PID for verification
PATIENT_PID=$(openemr_query "SELECT pid FROM patient_data WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME' LIMIT 1" 2>/dev/null || echo "0")
echo "$PATIENT_PID" > /tmp/target_patient_pid.txt
echo "Target patient PID: $PATIENT_PID"

# Ensure patient starts as active (status = 1) for valid test
if [ "$INITIAL_STATUS" = "0" ]; then
    echo "Patient is already inactive, resetting to active for test..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "UPDATE patient_data SET active=1 WHERE fname='$PATIENT_FNAME' AND lname='$PATIENT_LNAME'" 2>/dev/null
    echo "1" > /tmp/initial_patient_status.txt
    echo "Patient status reset to active"
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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Mark Patient Inactive Task Setup Complete ==="
echo ""
echo "Task: Mark patient Maria Hickle as inactive"
echo "Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "DOB: $PATIENT_DOB"
echo "Current Status: Active"
echo "Reason for inactivation: Patient relocated out of state"
echo ""
echo "Instructions:"
echo "  1. Log in (admin / pass)"
echo "  2. Search for patient Maria Hickle"
echo "  3. Open Demographics → Edit"
echo "  4. Uncheck 'Patient Active' or change status to Inactive"
echo "  5. Save changes"
echo ""