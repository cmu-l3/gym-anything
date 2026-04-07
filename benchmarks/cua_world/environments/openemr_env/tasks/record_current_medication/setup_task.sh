#!/bin/bash
# Setup script for Record Current Medication task

echo "=== Setting up Record Current Medication Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial medication count for this patient (prescriptions table)
echo "Recording initial medication counts..."
INITIAL_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_RX_COUNT" > /tmp/initial_rx_count.txt
echo "Initial prescriptions count for patient: $INITIAL_RX_COUNT"

# Record initial medication list count (lists table with type='medication')
INITIAL_MEDLIST_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='medication'" 2>/dev/null || echo "0")
echo "$INITIAL_MEDLIST_COUNT" > /tmp/initial_medlist_count.txt
echo "Initial medication list count for patient: $INITIAL_MEDLIST_COUNT"

# Check if Metformin already exists (for debugging)
EXISTING_METFORMIN=$(openemr_query "SELECT id, drug FROM prescriptions WHERE patient_id=$PATIENT_PID AND LOWER(drug) LIKE '%metformin%'" 2>/dev/null || echo "")
if [ -n "$EXISTING_METFORMIN" ]; then
    echo "WARNING: Metformin already exists in prescriptions: $EXISTING_METFORMIN"
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

# Take initial screenshot for audit
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved"

echo ""
echo "=== Record Current Medication Task Setup Complete ==="
echo ""
echo "TASK: Record Current Medication (Medication Reconciliation)"
echo "============================================================"
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo ""
echo "Medication to Add:"
echo "  Drug: Metformin HCl 500mg tablet"
echo "  Directions: Take 1 tablet twice daily with meals"
echo "  Type: External/Patient-reported (not a new prescription)"
echo "  Start Date: 2024-01-15"
echo ""
echo "Login credentials: admin / pass"
echo ""
echo "Navigate to patient's Medications section and add this"
echo "to their active medication list."
echo ""