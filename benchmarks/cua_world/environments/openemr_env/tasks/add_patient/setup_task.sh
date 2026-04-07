#!/bin/bash
# Setup script for Add Patient task

echo "=== Setting up Add Patient Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial patient count for verification (via Docker)
echo "Recording initial patient count..."
INITIAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM patient_data" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_patient_count
echo "Initial patient count: $INITIAL_COUNT"

# Ensure Firefox is running and focused on OpenEMR
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

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Click on center of screen to ensure desktop is selected
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 0.5

# Focus Firefox again
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Add Patient Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR if not already logged in"
echo "     - Username: admin"
echo "     - Password: pass"
echo ""
echo "  2. Navigate to Patient > New/Search"
echo ""
echo "  3. Fill in the patient details:"
echo "     - First Name: John"
echo "     - Last Name: TestPatient"
echo "     - Date of Birth: March 15, 1985 (1985-03-15)"
echo "     - Sex: Male"
echo ""
echo "  4. Save the patient record"
echo ""
