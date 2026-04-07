#!/bin/bash
# Setup script for Record Smoking Status Change Task

echo "=== Setting up Record Smoking Status Change Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=6
PATIENT_NAME="Marcus Weber"
INITIAL_STATUS="Current Every Day Smoker"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Get current tobacco status and record it
echo "Recording initial smoking status..."
CURRENT_TOBACCO=$(openemr_query "SELECT tobacco FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Current tobacco field value: '$CURRENT_TOBACCO'"
echo "$CURRENT_TOBACCO" > /tmp/initial_smoking_status.txt

# If tobacco field is empty or not set to current smoker, set it
if [ -z "$CURRENT_TOBACCO" ] || [ "$CURRENT_TOBACCO" = "NULL" ]; then
    echo "Setting initial smoking status to '$INITIAL_STATUS'..."
    openemr_query "UPDATE patient_data SET tobacco='$INITIAL_STATUS' WHERE pid=$PATIENT_PID" 2>/dev/null
    echo "$INITIAL_STATUS" > /tmp/initial_smoking_status.txt
    echo "Initial status set."
elif ! echo "$CURRENT_TOBACCO" | grep -qi "current"; then
    echo "Tobacco status exists but is not 'current smoker', updating..."
    openemr_query "UPDATE patient_data SET tobacco='$INITIAL_STATUS' WHERE pid=$PATIENT_PID" 2>/dev/null
    echo "$INITIAL_STATUS" > /tmp/initial_smoking_status.txt
fi

# Verify the status was set correctly
VERIFY_STATUS=$(openemr_query "SELECT tobacco FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Verified tobacco status: '$VERIFY_STATUS'"

# Also check history_data table for social history
echo "Checking history_data table..."
HISTORY_CHECK=$(openemr_query "SELECT id, tobacco FROM history_data WHERE pid=$PATIENT_PID ORDER BY date DESC LIMIT 1" 2>/dev/null)
if [ -n "$HISTORY_CHECK" ]; then
    echo "History data found: $HISTORY_CHECK"
    HISTORY_TOBACCO=$(echo "$HISTORY_CHECK" | cut -f2)
    echo "$HISTORY_TOBACCO" > /tmp/initial_history_tobacco.txt
else
    echo "No history_data entry found for patient"
    echo "" > /tmp/initial_history_tobacco.txt
fi

# Record modification timestamp of patient record
INITIAL_MTIME=$(openemr_query "SELECT UNIX_TIMESTAMP(date) FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_MTIME" > /tmp/initial_patient_mtime.txt
echo "Initial patient record modification time: $INITIAL_MTIME"

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
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Record Smoking Status Change Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Current Smoking Status: $VERIFY_STATUS"
echo ""
echo "TASK: Update this patient's smoking status from 'Current Every Day Smoker'"
echo "      to 'Former Smoker' because the patient has quit smoking."
echo ""
echo "Login credentials: admin / pass"
echo ""