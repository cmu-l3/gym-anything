#!/bin/bash
# Setup script for Prescribe Medication Task

echo "=== Setting up Prescribe Medication Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=7
PATIENT_NAME="Milo Feil"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Check for existing allergies (should have none or no penicillin allergy)
echo "Checking patient allergies..."
ALLERGY_CHECK=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND type='allergy'" 2>/dev/null)
if [ -z "$ALLERGY_CHECK" ]; then
    echo "No allergies documented for patient (safe to prescribe penicillin)"
else
    echo "Patient allergies: $ALLERGY_CHECK"
    # Check if penicillin allergy exists
    if echo "$ALLERGY_CHECK" | grep -qi "penicillin\|amoxicillin\|pcn"; then
        echo "WARNING: Patient has penicillin allergy - task may need alternative antibiotic"
    fi
fi

# Record initial prescription count for this patient
echo "Recording initial prescription count..."
INITIAL_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_RX_COUNT" > /tmp/initial_rx_count
echo "Initial prescription count for patient: $INITIAL_RX_COUNT"

# Record existing amoxicillin prescriptions to detect duplicates
echo "Checking for existing amoxicillin prescriptions..."
EXISTING_AMOX=$(openemr_query "SELECT id, drug, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID AND LOWER(drug) LIKE '%amoxicillin%' ORDER BY id DESC LIMIT 3" 2>/dev/null)
if [ -n "$EXISTING_AMOX" ]; then
    echo "Existing amoxicillin prescriptions: $EXISTING_AMOX"
    echo "$EXISTING_AMOX" > /tmp/existing_amox_rx
else
    echo "No existing amoxicillin prescriptions"
    echo "" > /tmp/existing_amox_rx
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
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

# Take initial screenshot for audit verification
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved to /tmp/task_start_screenshot.png"

echo ""
echo "=== Prescribe Medication Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Required Prescription: Amoxicillin 500 MG, quantity 30, for strep throat"
echo ""
