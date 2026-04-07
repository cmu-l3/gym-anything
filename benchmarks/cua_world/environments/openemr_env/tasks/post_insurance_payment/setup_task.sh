#!/bin/bash
# Setup script for Post Insurance Payment Task

echo "=== Setting up Post Insurance Payment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (CRITICAL for anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial ar_activity count for this patient (anti-gaming check)
echo "Recording initial payment activity count..."
INITIAL_AR_COUNT=$(openemr_query "SELECT COUNT(*) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_AR_COUNT" > /tmp/initial_ar_count
echo "Initial ar_activity count for patient: $INITIAL_AR_COUNT"

# Record initial total payments for patient
INITIAL_PAYMENTS=$(openemr_query "SELECT COALESCE(SUM(pay_amount), 0) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_PAYMENTS" > /tmp/initial_payments_total
echo "Initial total payments for patient: $INITIAL_PAYMENTS"

# Ensure an encounter with billing charges exists for this patient
echo "Checking for billable encounters..."
ENCOUNTER_CHECK=$(openemr_query "SELECT encounter FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY encounter DESC LIMIT 1" 2>/dev/null)

if [ -z "$ENCOUNTER_CHECK" ]; then
    echo "Creating test encounter for patient..."
    # Create an encounter
    openemr_query "INSERT INTO form_encounter (date, reason, facility_id, pid, encounter, onset_date, billing_facility) VALUES (CURDATE(), 'Office Visit', 3, $PATIENT_PID, (SELECT COALESCE(MAX(e2.encounter),0)+1 FROM form_encounter e2), CURDATE(), 3)" 2>/dev/null
    ENCOUNTER_CHECK=$(openemr_query "SELECT encounter FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY encounter DESC LIMIT 1" 2>/dev/null)
    echo "Created encounter: $ENCOUNTER_CHECK"
fi

echo "Using encounter: $ENCOUNTER_CHECK"

# Ensure billing charges exist for the encounter
BILLING_CHECK=$(openemr_query "SELECT id FROM billing WHERE pid=$PATIENT_PID AND encounter=$ENCOUNTER_CHECK AND fee > 0 LIMIT 1" 2>/dev/null)

if [ -z "$BILLING_CHECK" ]; then
    echo "Creating billing charges for encounter..."
    openemr_query "INSERT INTO billing (date, code_type, code, pid, encounter, code_text, modifier, units, fee, billed, activity, authorized) VALUES (CURDATE(), 'CPT4', '99213', $PATIENT_PID, $ENCOUNTER_CHECK, 'Office Visit - Established Patient', '', 1, 100.00, 1, 1, 1)" 2>/dev/null
    echo "Created $100.00 office visit charge"
else
    echo "Billing charges already exist"
fi

# Verify the charges
CHARGE_TOTAL=$(openemr_query "SELECT COALESCE(SUM(fee), 0) FROM billing WHERE pid=$PATIENT_PID AND encounter=$ENCOUNTER_CHECK AND activity=1" 2>/dev/null || echo "0")
echo "Total charges for encounter: \$$CHARGE_TOTAL"

# Calculate current balance (charges - payments - adjustments)
CURRENT_PAYMENTS=$(openemr_query "SELECT COALESCE(SUM(pay_amount), 0) FROM ar_activity WHERE pid=$PATIENT_PID AND encounter=$ENCOUNTER_CHECK" 2>/dev/null || echo "0")
CURRENT_ADJUSTMENTS=$(openemr_query "SELECT COALESCE(SUM(adj_amount), 0) FROM ar_activity WHERE pid=$PATIENT_PID AND encounter=$ENCOUNTER_CHECK" 2>/dev/null || echo "0")

echo "Current payments on encounter: \$$CURRENT_PAYMENTS"
echo "Current adjustments on encounter: \$$CURRENT_ADJUSTMENTS"

# Store encounter number for verification
echo "$ENCOUNTER_CHECK" > /tmp/task_encounter_id

# Ensure Firefox is running on OpenEMR
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
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo ""
echo "=== Post Insurance Payment Task Setup Complete ==="
echo ""
echo "SCENARIO: You are a medical biller at a clinic."
echo ""
echo "EOB DETAILS FROM BLUE CROSS BLUE SHIELD:"
echo "  Patient: $PATIENT_NAME (DOB: 1992-06-30)"
echo "  Service: Office Visit (CPT 99213)"
echo "  Billed Amount: \$100.00"
echo "  Allowed Amount: \$85.00"
echo "  Insurance Payment: \$85.00"
echo "  Contractual Adjustment: \$15.00"
echo "  Check/Reference: EOB2024-7834"
echo ""
echo "TASK: Post this insurance payment to the patient's account."
echo ""
echo "Login: admin / pass"
echo ""