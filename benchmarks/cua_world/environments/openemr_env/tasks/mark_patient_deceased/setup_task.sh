#!/bin/bash
# Setup script for Mark Patient as Deceased task

echo "=== Setting up Mark Patient as Deceased Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Configuration
PATIENT_PID=7
PATIENT_FNAME="Deandre"
PATIENT_LNAME="Reichel"
EXPECTED_DEATH_DATE="2024-03-15"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_FNAME $PATIENT_LNAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)

if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient pid=$PATIENT_PID not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial deceased status (should be NULL or empty)
echo "Recording initial deceased status..."
INITIAL_DECEASED=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT IFNULL(deceased_date, 'NULL') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "$INITIAL_DECEASED" > /tmp/initial_deceased_status.txt
echo "Initial deceased_date: $INITIAL_DECEASED"

# If patient is already marked as deceased, reset for clean test
if [ "$INITIAL_DECEASED" != "NULL" ] && [ -n "$INITIAL_DECEASED" ]; then
    echo "Resetting patient deceased status for clean test..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "UPDATE patient_data SET deceased_date=NULL, deceased_reason=NULL WHERE pid=$PATIENT_PID" 2>/dev/null
    
    # Verify reset
    RESET_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT IFNULL(deceased_date, 'NULL') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
    echo "After reset, deceased_date: $RESET_CHECK"
    echo "NULL" > /tmp/initial_deceased_status.txt
fi

# Record initial modification timestamp
INITIAL_MOD_TIME=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT UNIX_TIMESTAMP(date) FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_MOD_TIME" > /tmp/initial_mod_time.txt
echo "Initial record modification timestamp: $INITIAL_MOD_TIME"

# Ensure Firefox is running with OpenEMR
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
sleep 2
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox window focused and maximized: $WID"
fi

# Take initial screenshot for audit
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Mark Patient as Deceased Task Setup Complete ==="
echo ""
echo "TASK: Mark patient as deceased"
echo "================================"
echo ""
echo "Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "Date of Birth: 1926-09-11"
echo ""
echo "Death Information to Record:"
echo "  - Date of Death: $EXPECTED_DEATH_DATE"
echo "  - Cause: Natural causes (if field available)"
echo ""
echo "Login credentials:"
echo "  - Username: admin"
echo "  - Password: pass"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR"
echo "  2. Search for patient 'Deandre Reichel'"
echo "  3. Open patient record and navigate to demographics"
echo "  4. Find and update the deceased/death date field"
echo "  5. Save changes"
echo ""