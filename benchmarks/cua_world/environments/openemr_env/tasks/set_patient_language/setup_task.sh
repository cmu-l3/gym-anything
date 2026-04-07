#!/bin/bash
# Setup script for Set Patient Language Task

echo "=== Setting up Set Patient Language Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp for anti-gaming
echo "Recording task start time..."
date +%s > /tmp/task_start_timestamp
TASK_START=$(cat /tmp/task_start_timestamp)
echo "Task start timestamp: $TASK_START"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, language FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial language value (critical for anti-gaming)
echo "Recording initial language preference..."
INITIAL_LANGUAGE=$(openemr_query "SELECT COALESCE(language, '') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null | tr -d '\n')
echo "$INITIAL_LANGUAGE" > /tmp/initial_language.txt
echo "Initial language value: '$INITIAL_LANGUAGE'"

# If language is already Spanish, clear it for the task
# This ensures the task is meaningful
if echo "$INITIAL_LANGUAGE" | grep -qi "spanish\|spa\|^es$"; then
    echo "Language is already set to Spanish - clearing for task..."
    openemr_query "UPDATE patient_data SET language='' WHERE pid=$PATIENT_PID" 2>/dev/null
    INITIAL_LANGUAGE=""
    echo "" > /tmp/initial_language.txt
    echo "Language cleared - agent must set it to Spanish"
fi

# Record initial state hash for verification
INITIAL_STATE=$(openemr_query "SELECT pid, fname, lname, language, DATE_FORMAT(date, '%Y-%m-%d %H:%i:%s') as modified FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "$INITIAL_STATE" > /tmp/initial_patient_state.txt
echo "Initial patient state recorded"

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
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Set Patient Language Task Setup Complete ==="
echo ""
echo "Task: Set preferred language for patient $PATIENT_NAME to Spanish"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (Username: admin, Password: pass)"
echo "  2. Search for and select patient: $PATIENT_NAME"
echo "  3. Navigate to Demographics editing"
echo "  4. Find the Language preference field"
echo "  5. Set language to 'Spanish'"
echo "  6. Save the changes"
echo ""
echo "Patient PID: $PATIENT_PID"
echo "Current language: '$(cat /tmp/initial_language.txt)' (should be blank)"
echo ""