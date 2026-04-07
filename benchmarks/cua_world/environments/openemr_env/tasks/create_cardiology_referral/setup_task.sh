#!/bin/bash
# Setup script for Create Cardiology Referral Task

echo "=== Setting up Create Cardiology Referral Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify hypertension condition exists for this patient
echo "Verifying hypertension diagnosis..."
HTN_CHECK=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (LOWER(title) LIKE '%hypertension%' OR diagnosis LIKE '%59621000%' OR diagnosis LIKE '%I10%')" 2>/dev/null)
if [ -z "$HTN_CHECK" ]; then
    echo "WARNING: Hypertension diagnosis not found for patient - task may still proceed"
else
    echo "Hypertension confirmed: $HTN_CHECK"
fi

# Record initial referral count for this patient (for anti-gaming detection)
echo "Recording initial referral count..."
INITIAL_REFERRAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM transactions WHERE pid=$PATIENT_PID AND LOWER(title) LIKE '%referral%'" 2>/dev/null || echo "0")
echo "$INITIAL_REFERRAL_COUNT" > /tmp/initial_referral_count
echo "Initial referral count for patient: $INITIAL_REFERRAL_COUNT"

# Also record all existing referral IDs so we can detect new ones
echo "Recording existing referral IDs..."
EXISTING_IDS=$(openemr_query "SELECT id FROM transactions WHERE pid=$PATIENT_PID AND LOWER(title) LIKE '%referral%' ORDER BY id" 2>/dev/null || echo "")
echo "$EXISTING_IDS" > /tmp/existing_referral_ids
echo "Existing referral IDs: $EXISTING_IDS"

# Record total transaction count as another anti-gaming measure
TOTAL_TX_COUNT=$(openemr_query "SELECT COUNT(*) FROM transactions" 2>/dev/null || echo "0")
echo "$TOTAL_TX_COUNT" > /tmp/initial_total_tx_count
echo "Initial total transaction count: $TOTAL_TX_COUNT"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window to appear
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

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Create Cardiology Referral Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Condition: Hypertension (requires cardiology referral)"
echo ""
echo "Task: Create a referral to Cardiology for hypertension evaluation"
echo ""
echo "Navigation hint: Patient > Transactions > Add Referral"
echo "                 or Miscellaneous > New/Search Transactions"
echo ""