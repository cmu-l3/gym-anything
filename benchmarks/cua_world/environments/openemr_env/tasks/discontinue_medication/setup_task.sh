#!/bin/bash
# Setup script for Discontinue Medication task

echo "=== Setting up Discontinue Medication Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"
MEDICATION_PATTERN="amLODIPine"

# Record task start time (critical for anti-gaming)
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

# Check current medication status and record baseline
echo ""
echo "Recording baseline medication state..."
BASELINE_MED=$(openemr_query "SELECT id, drug, active, date_modified, rxnorm_drugcode FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%$MEDICATION_PATTERN%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "Current medication record: $BASELINE_MED"

# Parse baseline data
if [ -n "$BASELINE_MED" ]; then
    BASELINE_ID=$(echo "$BASELINE_MED" | cut -f1)
    BASELINE_DRUG=$(echo "$BASELINE_MED" | cut -f2)
    BASELINE_ACTIVE=$(echo "$BASELINE_MED" | cut -f3)
    BASELINE_MODIFIED=$(echo "$BASELINE_MED" | cut -f4)
    BASELINE_RXNORM=$(echo "$BASELINE_MED" | cut -f5)
    
    echo "  Prescription ID: $BASELINE_ID"
    echo "  Drug: $BASELINE_DRUG"
    echo "  Active: $BASELINE_ACTIVE"
    echo "  Last Modified: $BASELINE_MODIFIED"
else
    echo "WARNING: Medication not found. Will attempt to verify it exists or create it."
    BASELINE_ID=""
    BASELINE_ACTIVE=""
fi

# If medication doesn't exist or is not active, we need to ensure it is for the task
if [ -z "$BASELINE_ID" ] || [ "$BASELINE_ACTIVE" != "1" ]; then
    echo ""
    echo "Ensuring medication is active for the task..."
    
    # Check if any prescription exists for this patient with this drug
    EXISTING=$(openemr_query "SELECT id FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%$MEDICATION_PATTERN%' LIMIT 1" 2>/dev/null)
    
    if [ -n "$EXISTING" ]; then
        # Reactivate existing prescription
        echo "Reactivating existing prescription (id=$EXISTING)..."
        openemr_query "UPDATE prescriptions SET active=1 WHERE id=$EXISTING" 2>/dev/null
    else
        echo "No existing prescription found - checking Synthea data loaded correctly"
    fi
    
    # Re-query to get updated baseline
    BASELINE_MED=$(openemr_query "SELECT id, drug, active, date_modified FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%$MEDICATION_PATTERN%' AND active=1 ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# Save baseline state to JSON
BASELINE_ACTIVE_STATUS=$(openemr_query "SELECT active FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%$MEDICATION_PATTERN%' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "unknown")
BASELINE_MED_ID=$(openemr_query "SELECT id FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%$MEDICATION_PATTERN%' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "0")

cat > /tmp/baseline_medication_state.json << EOF
{
    "patient_pid": $PATIENT_PID,
    "medication_id": "${BASELINE_MED_ID:-0}",
    "medication_pattern": "$MEDICATION_PATTERN",
    "initial_active_status": "${BASELINE_ACTIVE_STATUS:-unknown}",
    "task_start_timestamp": $(cat /tmp/task_start_time.txt),
    "setup_time": "$(date -Iseconds)"
}
EOF

echo ""
echo "Baseline state saved to /tmp/baseline_medication_state.json:"
cat /tmp/baseline_medication_state.json

# Ensure Firefox is running on OpenEMR login page
echo ""
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox for clean state
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

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
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Discontinue Medication Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Medication to discontinue: amLODIPine / Hydrochlorothiazide / Olmesartan combination"
echo "Reason for discontinuation: Peripheral edema (ankle swelling)"
echo ""
echo "Login credentials: admin / pass"
echo ""