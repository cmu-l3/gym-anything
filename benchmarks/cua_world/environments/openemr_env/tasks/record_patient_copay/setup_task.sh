#!/bin/bash
# Setup script for Record Patient Copay Payment task

echo "=== Setting up Record Patient Copay Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=4
PATIENT_NAME="Jude Sauer"

# Record task start timestamp (critical for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start timestamp: $TASK_START ($(date -d @$TASK_START))"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial payment count for this patient across all payment tables
echo "Recording initial payment state..."

# Check payments table
INITIAL_PAYMENTS=$(openemr_query "SELECT COUNT(*) FROM payments WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_PAYMENTS" > /tmp/initial_payments_count.txt
echo "Initial payments table count for patient: $INITIAL_PAYMENTS"

# Check ar_activity table (another common payment location)
INITIAL_AR_ACTIVITY=$(openemr_query "SELECT COUNT(*) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_AR_ACTIVITY" > /tmp/initial_ar_activity_count.txt
echo "Initial ar_activity count for patient: $INITIAL_AR_ACTIVITY"

# Check ar_session table
INITIAL_AR_SESSION=$(openemr_query "SELECT COUNT(*) FROM ar_session WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_AR_SESSION" > /tmp/initial_ar_session_count.txt
echo "Initial ar_session count for patient: $INITIAL_AR_SESSION"

# Get total payment count across all patients (for general comparison)
TOTAL_PAYMENTS=$(openemr_query "SELECT COUNT(*) FROM payments" 2>/dev/null || echo "0")
echo "$TOTAL_PAYMENTS" > /tmp/initial_total_payments.txt
echo "Total payments in system: $TOTAL_PAYMENTS"

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
echo "=== Record Patient Copay Task Setup Complete ==="
echo ""
echo "TASK: Record a co-pay payment for patient $PATIENT_NAME"
echo ""
echo "Patient Information:"
echo "  - Name: $PATIENT_NAME"
echo "  - PID: $PATIENT_PID"
echo "  - DOB: 1975-04-11"
echo ""
echo "Payment to Record:"
echo "  - Amount: \$30.00"
echo "  - Method: Cash"
echo "  - Note: Copay for office visit"
echo ""
echo "Login Credentials:"
echo "  - Username: admin"
echo "  - Password: pass"
echo ""
echo "Navigate to Fees/Billing section to record the payment."
echo ""