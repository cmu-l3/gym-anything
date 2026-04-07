#!/bin/bash
# Setup script for Write Prescription Task

echo "=== Setting up Write Prescription Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=1
PATIENT_NAME="Tressa Gusikowski"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
TASK_START=$(cat /tmp/task_start_timestamp)
echo "Task start timestamp: $TASK_START ($(date -d @$TASK_START))"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial prescription count for this patient (critical for anti-gaming)
echo "Recording initial prescription count..."
INITIAL_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_RX_COUNT" > /tmp/initial_rx_count
echo "Initial prescription count for patient: $INITIAL_RX_COUNT"

# Also record total prescriptions in system
TOTAL_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions" 2>/dev/null || echo "0")
echo "$TOTAL_RX_COUNT" > /tmp/initial_total_rx_count
echo "Total prescriptions in system: $TOTAL_RX_COUNT"

# Record existing prescription IDs for this patient (to identify new ones)
EXISTING_RX_IDS=$(openemr_query "SELECT id FROM prescriptions WHERE patient_id=$PATIENT_PID ORDER BY id" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "$EXISTING_RX_IDS" > /tmp/existing_rx_ids
echo "Existing prescription IDs: $EXISTING_RX_IDS"

# Check for any existing Ciprofloxacin prescriptions (to detect gaming)
EXISTING_CIPRO=$(openemr_query "SELECT id, drug, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%Ciprofloxacin%'" 2>/dev/null)
if [ -n "$EXISTING_CIPRO" ]; then
    echo "WARNING: Patient already has Ciprofloxacin prescription(s):"
    echo "$EXISTING_CIPRO"
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
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved to /tmp/task_start_screenshot.png"

# Create initial state JSON for verifier
cat > /tmp/initial_state.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "patient_pid": $PATIENT_PID,
    "patient_name": "$PATIENT_NAME",
    "initial_rx_count": $INITIAL_RX_COUNT,
    "initial_total_rx_count": $TOTAL_RX_COUNT,
    "existing_rx_ids": "$EXISTING_RX_IDS"
}
EOF

echo ""
echo "=== Write Prescription Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Task: Write a prescription for Ciprofloxacin 500 MG"
echo ""
echo "Login credentials: admin / pass"
echo ""