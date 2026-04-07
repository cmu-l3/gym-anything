#!/bin/bash
# Setup script for Assign Patient Price Level Task

echo "=== Setting up Assign Patient Price Level Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=5
PATIENT_NAME="Alesha Harber"
INITIAL_PRICE_LEVEL="Standard"

# Record task start timestamp for anti-gaming
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

# Reset patient's price level to Standard for clean test
echo "Resetting price level to '$INITIAL_PRICE_LEVEL'..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "UPDATE patient_data SET pricelevel='$INITIAL_PRICE_LEVEL' WHERE pid=$PATIENT_PID" 2>/dev/null

# Record initial price level
CURRENT_PRICELEVEL=$(openemr_query "SELECT pricelevel FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "$CURRENT_PRICELEVEL" > /tmp/initial_price_level
echo "Initial price level: $CURRENT_PRICELEVEL"

# Ensure sliding fee price levels exist in the system
echo "Ensuring price level options exist..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
    INSERT IGNORE INTO list_options (list_id, option_id, title, seq, is_default, activity)
    VALUES 
    ('pricelev', 'Standard', 'Standard', 1, 1, 1),
    ('pricelev', 'Sliding 0', 'Sliding 0', 2, 0, 1),
    ('pricelev', 'Sliding 1', 'Sliding 1', 3, 0, 1),
    ('pricelev', 'Sliding 2', 'Sliding 2', 4, 0, 1);
" 2>/dev/null || true

# Verify price levels are available
echo "Available price levels:"
openemr_query "SELECT option_id, title FROM list_options WHERE list_id='pricelev' AND activity=1" 2>/dev/null

# Record the patient's last modification time for comparison
INITIAL_MOD_TIME=$(openemr_query "SELECT UNIX_TIMESTAMP(date) FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_MOD_TIME" > /tmp/initial_mod_time
echo "Initial modification timestamp: $INITIAL_MOD_TIME"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox for clean start
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
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

# Take initial screenshot for audit
sleep 2
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo ""
echo "=== Assign Patient Price Level Task Setup Complete ==="
echo ""
echo "Task: Assign sliding fee schedule price level to a patient"
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Current Price Level: $INITIAL_PRICE_LEVEL"
echo "Target Price Level: Sliding 1"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin / pass)"
echo "  2. Search for patient 'Alesha Harber'"
echo "  3. Open Demographics"
echo "  4. Find 'Price Level' in the Choices section"
echo "  5. Change from 'Standard' to 'Sliding 1'"
echo "  6. Save changes"
echo ""