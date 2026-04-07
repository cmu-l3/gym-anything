#!/bin/bash
# Setup script for Post Account Write-off Task

echo "=== Setting up Post Account Write-off Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
TASK_START=$(cat /tmp/task_start_time.txt)
echo "Task start timestamp: $TASK_START"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial AR activity count for this patient
echo "Recording initial billing/AR activity count..."
INITIAL_AR_COUNT=$(openemr_query "SELECT COUNT(*) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_AR_COUNT" > /tmp/initial_ar_count.txt
echo "Initial ar_activity count for patient: $INITIAL_AR_COUNT"

# Record initial ar_session count
INITIAL_SESSION_COUNT=$(openemr_query "SELECT COUNT(*) FROM ar_session WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_SESSION_COUNT" > /tmp/initial_session_count.txt
echo "Initial ar_session count for patient: $INITIAL_SESSION_COUNT"

# Record initial payments count (if table exists)
INITIAL_PAYMENTS_COUNT=$(openemr_query "SELECT COUNT(*) FROM payments WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_PAYMENTS_COUNT" > /tmp/initial_payments_count.txt
echo "Initial payments count for patient: $INITIAL_PAYMENTS_COUNT"

# Get max ar_activity sequence to detect new entries
MAX_AR_SEQ=$(openemr_query "SELECT COALESCE(MAX(sequence_no), 0) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$MAX_AR_SEQ" > /tmp/initial_ar_max_seq.txt
echo "Max ar_activity sequence: $MAX_AR_SEQ"

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
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Post Account Write-off Task Setup Complete ==="
echo ""
echo "TASK: Post a billing write-off adjustment"
echo "==========================================="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Amount: \$15.00"
echo "Reason: Small balance write-off - cost to collect exceeds balance"
echo ""
echo "Login credentials: admin / pass"
echo ""
echo "Steps:"
echo "1. Log in to OpenEMR"
echo "2. Find patient Jayson Fadel"
echo "3. Go to Fees/Billing section"
echo "4. Post an adjustment of \$15.00"
echo "5. Add note about small balance write-off"
echo "6. Save the transaction"
echo ""