#!/bin/bash
# Setup script for Add Patient Safety Alert Task

echo "=== Setting up Add Patient Safety Alert Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=4
PATIENT_NAME="Faye Conn"

# Record task start timestamp for anti-gaming
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

# Record initial alert count for this patient
# OpenEMR stores alerts in the 'lists' table with various types
echo "Recording initial alert/warning count..."

# Count alerts in lists table (type can be 'alert', 'warning', 'medical_problem' used as alert, etc.)
INITIAL_ALERT_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND (type='alert' OR type='warning' OR type='flag' OR (type='medical_problem' AND title LIKE '%alert%'))" 2>/dev/null || echo "0")
echo "$INITIAL_ALERT_COUNT" > /tmp/initial_alert_count.txt
echo "Initial alert count for patient: $INITIAL_ALERT_COUNT"

# Also record total lists count for this patient (broader check)
INITIAL_LISTS_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_LISTS_COUNT" > /tmp/initial_lists_count.txt
echo "Initial total lists count for patient: $INITIAL_LISTS_COUNT"

# Check for any existing venipuncture-related alerts (to detect cheating with pre-existing data)
EXISTING_VENIPUNCTURE=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND (LOWER(title) LIKE '%venipuncture%' OR LOWER(title) LIKE '%iv access%' OR LOWER(title) LIKE '%difficult iv%')" 2>/dev/null || echo "")
if [ -n "$EXISTING_VENIPUNCTURE" ]; then
    echo "WARNING: Existing venipuncture-related entry found: $EXISTING_VENIPUNCTURE"
    echo "$EXISTING_VENIPUNCTURE" > /tmp/existing_venipuncture_alert.txt
else
    echo "No existing venipuncture alerts found (good)"
    echo "" > /tmp/existing_venipuncture_alert.txt
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
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Add Patient Safety Alert Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1959-03-16)"
echo ""
echo "  1. Log in to OpenEMR (admin / pass)"
echo "  2. Search for and open patient '$PATIENT_NAME'"
echo "  3. Add a safety alert for 'Difficult Venipuncture'"
echo "  4. Include clinical details about scarring and recommendations"
echo "  5. Save the alert"
echo ""