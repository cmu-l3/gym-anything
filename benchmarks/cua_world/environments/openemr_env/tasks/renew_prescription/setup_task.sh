#!/bin/bash
# Setup script for Renew Prescription task

echo "=== Setting up Renew Prescription Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify existing prescription exists for this patient
echo "Verifying existing prescription for amLODIPine..."
EXISTING_RX=$(openemr_query "SELECT id, drug, quantity, refills FROM prescriptions WHERE patient_id=$PATIENT_PID AND LOWER(drug) LIKE '%amlodipine%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
if [ -z "$EXISTING_RX" ]; then
    echo "WARNING: No existing amLODIPine prescription found for patient"
    echo "Task may still proceed - agent can create a new prescription"
else
    echo "Existing prescription found: $EXISTING_RX"
fi

# Record initial prescription count for this patient
echo "Recording initial prescription count..."
INITIAL_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_RX_COUNT" > /tmp/initial_rx_count.txt
echo "Initial prescription count for patient $PATIENT_PID: $INITIAL_RX_COUNT"

# Record initial total prescription count (for detecting any new prescriptions)
INITIAL_TOTAL_RX=$(openemr_query "SELECT COUNT(*) FROM prescriptions" 2>/dev/null || echo "0")
echo "$INITIAL_TOTAL_RX" > /tmp/initial_total_rx_count.txt
echo "Initial total prescription count: $INITIAL_TOTAL_RX"

# Get the highest prescription ID before task starts
MAX_RX_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM prescriptions" 2>/dev/null || echo "0")
echo "$MAX_RX_ID" > /tmp/initial_max_rx_id.txt
echo "Maximum prescription ID before task: $MAX_RX_ID"

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
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Renew Prescription Task Setup Complete ==="
echo ""
echo "TASK: Renew Prescription for $PATIENT_NAME"
echo "============================================"
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo "Medication: amLODIPine combination antihypertensive"
echo "Renewal parameters: Quantity=90, Refills=3"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin/pass)"
echo "  2. Find patient Jayson Fadel"
echo "  3. Navigate to prescriptions/medications"
echo "  4. Renew the amLODIPine prescription"
echo "  5. Set Quantity=90, Refills=3"
echo "  6. Save the prescription"
echo ""