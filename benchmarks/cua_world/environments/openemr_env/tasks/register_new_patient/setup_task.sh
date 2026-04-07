#!/bin/bash
# Setup script for Register New Patient task

echo "=== Setting up Register New Patient Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Expected patient details
EXPECTED_FNAME="Marcus"
EXPECTED_LNAME="Wellington"

# Clean up any pre-existing test patient (for re-runs)
echo "Checking for pre-existing test patient..."
EXISTING_PATIENT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid FROM patient_data WHERE fname='$EXPECTED_FNAME' AND lname='$EXPECTED_LNAME'" 2>/dev/null)

if [ -n "$EXISTING_PATIENT" ]; then
    echo "Found existing patient with pid=$EXISTING_PATIENT, removing for clean test..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "DELETE FROM patient_data WHERE fname='$EXPECTED_FNAME' AND lname='$EXPECTED_LNAME'" 2>/dev/null
    echo "Existing test patient removed"
fi

# Record initial patient count for verification
echo "Recording initial patient count..."
INITIAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM patient_data" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_patient_count
echo "Initial patient count: $INITIAL_COUNT"

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START ($(date -d @$TASK_START))"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill any existing Firefox instances for clean start
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

# Dismiss any Firefox first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for audit
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved to /tmp/task_initial_screenshot.png"

echo ""
echo "=== Register New Patient Task Setup Complete ==="
echo ""
echo "TASK: Register a new patient with the following information:"
echo ""
echo "  First Name:     Marcus"
echo "  Last Name:      Wellington"
echo "  Date of Birth:  1978-11-23 (November 23, 1978)"
echo "  Sex:            Male"
echo "  Street Address: 742 Evergreen Terrace"
echo "  City:           Springfield"
echo "  State:          Massachusetts"
echo "  Postal Code:    01103"
echo "  Phone (Mobile): 413-555-0199"
echo "  Email:          marcus.wellington@email.test"
echo ""
echo "Login credentials: admin / pass"
echo ""