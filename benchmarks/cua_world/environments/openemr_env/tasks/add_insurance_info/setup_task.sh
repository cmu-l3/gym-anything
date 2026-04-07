#!/bin/bash
# Setup script for Add Insurance Info task

echo "=== Setting up Add Insurance Info Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=5
PATIENT_NAME="Philip Kuvalis"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    echo "Checking available patients..."
    openemr_query "SELECT pid, fname, lname FROM patient_data ORDER BY pid LIMIT 10" 2>/dev/null
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Clear any existing insurance for this patient (clean starting state)
echo "Clearing any existing insurance records for patient..."
EXISTING_INS=$(openemr_query "SELECT COUNT(*) FROM insurance_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Existing insurance records before cleanup: $EXISTING_INS"

if [ "$EXISTING_INS" -gt "0" ]; then
    echo "Removing existing insurance records for clean test state..."
    openemr_query "DELETE FROM insurance_data WHERE pid=$PATIENT_PID" 2>/dev/null || true
fi

# Record initial insurance count (should be 0 after cleanup)
INITIAL_INS_COUNT=$(openemr_query "SELECT COUNT(*) FROM insurance_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_INS_COUNT" > /tmp/initial_insurance_count
echo "Initial insurance count for patient: $INITIAL_INS_COUNT"

# Also record total insurance records in system (for cross-check)
TOTAL_INS_COUNT=$(openemr_query "SELECT COUNT(*) FROM insurance_data" 2>/dev/null || echo "0")
echo "$TOTAL_INS_COUNT" > /tmp/initial_total_insurance_count
echo "Initial total insurance records in system: $TOTAL_INS_COUNT"

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

# Take initial screenshot for audit
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved to /tmp/task_start_screenshot.png"

echo ""
echo "=== Add Insurance Info Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1990-04-21)"
echo ""
echo "Insurance Details to Add:"
echo "  Company: Blue Cross Blue Shield"
echo "  Plan: PPO Standard"
echo "  Policy Number: XWP845621379"
echo "  Group Number: GRP7845210"
echo "  Subscriber: Self"
echo "  Effective Date: 2024-01-01"
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""