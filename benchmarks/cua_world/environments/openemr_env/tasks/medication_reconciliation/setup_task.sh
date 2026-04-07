#!/bin/bash
# Setup script for Medication Reconciliation Task

echo "=== Setting up Medication Reconciliation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=25
PATIENT_NAME="Edmund Walker"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial prescription count for this patient
echo "Recording initial prescription count..."
INITIAL_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_RX_COUNT" > /tmp/initial_rx_count
echo "Initial prescription count for patient: $INITIAL_RX_COUNT"

# Record which target medications already exist (for adversarial checking)
echo "Checking for pre-existing target medications..."
for DRUG in "Lisinopril" "Metformin" "Atorvastatin" "Aspirin" "Omeprazole"; do
    COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%$DRUG%'" 2>/dev/null || echo "0")
    echo "$DRUG: $COUNT" >> /tmp/initial_target_meds
    echo "  $DRUG prescriptions: $COUNT"
done

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
date +%Y-%m-%d > /tmp/task_start_date
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

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
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved to /tmp/task_start_screenshot.png"

echo ""
echo "=== Medication Reconciliation Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Task: Add patient-reported medications to reconcile the EHR"
echo ""
echo "Target medications to add:"
echo "  1. Lisinopril 20 mg - daily"
echo "  2. Metformin 500 mg - BID"
echo "  3. Atorvastatin 40 mg - daily"
echo "  4. Aspirin 81 mg - daily"
echo "  5. Omeprazole 20 mg - daily"
echo ""
