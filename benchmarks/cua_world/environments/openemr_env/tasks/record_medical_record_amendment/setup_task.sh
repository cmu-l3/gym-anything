#!/bin/bash
# Setup script for Record Medical Record Amendment Task

echo "=== Setting up Record Medical Record Amendment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial amendment count for this patient
echo "Recording initial amendment count..."
INITIAL_AMENDMENT_COUNT=$(openemr_query "SELECT COUNT(*) FROM amendments WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_AMENDMENT_COUNT" > /tmp/initial_amendment_count
echo "Initial amendment count for patient: $INITIAL_AMENDMENT_COUNT"

# Also record total amendments count (for detecting amendments to wrong patient)
TOTAL_INITIAL_AMENDMENTS=$(openemr_query "SELECT COUNT(*) FROM amendments" 2>/dev/null || echo "0")
echo "$TOTAL_INITIAL_AMENDMENTS" > /tmp/total_initial_amendments
echo "Total initial amendments in system: $TOTAL_INITIAL_AMENDMENTS"

# Check if amendments table exists (OpenEMR version compatibility)
AMENDMENTS_TABLE_EXISTS=$(openemr_query "SHOW TABLES LIKE 'amendments'" 2>/dev/null)
if [ -z "$AMENDMENTS_TABLE_EXISTS" ]; then
    echo "WARNING: Amendments table not found - checking for alternate table names..."
    # Check for possible alternate names
    openemr_query "SHOW TABLES LIKE '%amend%'" 2>/dev/null
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

# Take initial screenshot for audit trail
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo ""
echo "=== Record Medical Record Amendment Task Setup Complete ==="
echo ""
echo "Target Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Initial amendments for patient: $INITIAL_AMENDMENT_COUNT"
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR (admin/pass)"
echo "  2. Find patient Jayson Fadel"
echo "  3. Navigate to Miscellaneous > Amendments"
echo "  4. Create new amendment documenting occupation correction"
echo "  5. Set status to Approved"
echo "  6. Save the amendment"
echo ""