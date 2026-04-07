#!/bin/bash
# Setup script for Review Lab Results task

echo "=== Setting up Review Lab Results Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=4
PATIENT_NAME="Abraham Gutmann"

# Record task start timestamp for anti-gaming verification
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

# Record initial state - count of reviewed results and notes
echo "Recording initial state..."
INITIAL_REVIEWED_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_result WHERE result_status='final'" 2>/dev/null || echo "0")
echo "$INITIAL_REVIEWED_COUNT" > /tmp/initial_reviewed_count
echo "Initial reviewed results count: $INITIAL_REVIEWED_COUNT"

INITIAL_NOTE_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_note_count
echo "Initial notes count for patient: $INITIAL_NOTE_COUNT"

# Clean up any previous test procedure orders for this patient (to ensure clean state)
echo "Cleaning up previous test data..."
openemr_query "DELETE FROM procedure_result WHERE procedure_order_id IN (SELECT procedure_order_id FROM procedure_order WHERE patient_id=$PATIENT_PID AND procedure_order_id >= 900)" 2>/dev/null || true
openemr_query "DELETE FROM procedure_order WHERE patient_id=$PATIENT_PID AND procedure_order_id >= 900" 2>/dev/null || true

# Create a pending lab order for Abraham Gutmann
echo "Creating pending lab order..."
PROCEDURE_ORDER_ID=901
ORDER_DATE=$(date -d "-3 days" +%Y-%m-%d)
COLLECT_DATE=$(date -d "-1 day" +%Y-%m-%d)
REPORT_DATE=$(date -d "-1 day" +%Y-%m-%d)

# Insert procedure order
openemr_query "INSERT INTO procedure_order (
    procedure_order_id, provider_id, patient_id, encounter_id,
    date_collected, date_ordered, order_priority, order_status,
    clinical_hx, specimen_type, specimen_location
) VALUES (
    $PROCEDURE_ORDER_ID, 1, $PATIENT_PID, 0,
    '$COLLECT_DATE', '$ORDER_DATE', 'normal', 'pending',
    'Lipid panel for statin monitoring - annual checkup', 'blood', 'Lab'
) ON DUPLICATE KEY UPDATE order_status='pending', clinical_hx='Lipid panel for statin monitoring'" 2>/dev/null

echo "Created procedure order $PROCEDURE_ORDER_ID"

# Insert procedure order code (the test being ordered)
openemr_query "INSERT IGNORE INTO procedure_order_code (
    procedure_order_id, procedure_order_seq, procedure_code, procedure_name,
    diagnoses, procedure_source
) VALUES (
    $PROCEDURE_ORDER_ID, 1, '80061', 'Lipid Panel',
    'Z13.220', '1'
)" 2>/dev/null

# Insert procedure results (lab values) with 'preliminary' status (needs review)
echo "Creating pending lab results..."

# Total Cholesterol
openemr_query "INSERT INTO procedure_result (
    procedure_report_id, procedure_order_id, procedure_order_seq,
    date_report, result_status, result, units, 
    \`range\`, abnormal, comments, result_code, result_text, facility
) VALUES (
    9001, $PROCEDURE_ORDER_ID, 1,
    '$REPORT_DATE', 'preliminary', '185', 'mg/dL', 
    '< 200', '', 'Desirable range', 'CHOL', 'Total Cholesterol', 'Quest Diagnostics'
) ON DUPLICATE KEY UPDATE result_status='preliminary'" 2>/dev/null

# HDL Cholesterol
openemr_query "INSERT INTO procedure_result (
    procedure_report_id, procedure_order_id, procedure_order_seq,
    date_report, result_status, result, units, 
    \`range\`, abnormal, comments, result_code, result_text, facility
) VALUES (
    9002, $PROCEDURE_ORDER_ID, 1,
    '$REPORT_DATE', 'preliminary', '45', 'mg/dL', 
    '> 40', '', 'Acceptable level', 'HDL', 'HDL Cholesterol', 'Quest Diagnostics'
) ON DUPLICATE KEY UPDATE result_status='preliminary'" 2>/dev/null

# LDL Cholesterol
openemr_query "INSERT INTO procedure_result (
    procedure_report_id, procedure_order_id, procedure_order_seq,
    date_report, result_status, result, units, 
    \`range\`, abnormal, comments, result_code, result_text, facility
) VALUES (
    9003, $PROCEDURE_ORDER_ID, 1,
    '$REPORT_DATE', 'preliminary', '110', 'mg/dL', 
    '< 130', '', 'Optimal for patient on statin therapy', 'LDLC', 'LDL Cholesterol', 'Quest Diagnostics'
) ON DUPLICATE KEY UPDATE result_status='preliminary'" 2>/dev/null

# Triglycerides
openemr_query "INSERT INTO procedure_result (
    procedure_report_id, procedure_order_id, procedure_order_seq,
    date_report, result_status, result, units, 
    \`range\`, abnormal, comments, result_code, result_text, facility
) VALUES (
    9004, $PROCEDURE_ORDER_ID, 1,
    '$REPORT_DATE', 'preliminary', '150', 'mg/dL', 
    '< 150', '', 'At upper limit of normal', 'TRIG', 'Triglycerides', 'Quest Diagnostics'
) ON DUPLICATE KEY UPDATE result_status='preliminary'" 2>/dev/null

echo "Lab results created with preliminary status"

# Verify lab order was created
echo "Verifying lab order creation..."
LAB_CHECK=$(openemr_query "SELECT procedure_order_id, order_status FROM procedure_order WHERE procedure_order_id=$PROCEDURE_ORDER_ID" 2>/dev/null)
echo "Lab order: $LAB_CHECK"

RESULT_CHECK=$(openemr_query "SELECT COUNT(*) FROM procedure_result WHERE procedure_order_id=$PROCEDURE_ORDER_ID" 2>/dev/null)
echo "Lab results count: $RESULT_CHECK"

# Record the procedure order ID for verification
echo "$PROCEDURE_ORDER_ID" > /tmp/test_procedure_order_id

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
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved"

echo ""
echo "=== Review Lab Results Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Lab Test: Lipid Panel (pending review)"
echo "Procedure Order ID: $PROCEDURE_ORDER_ID"
echo ""
echo "Lab Values to Review:"
echo "  - Total Cholesterol: 185 mg/dL (normal: <200)"
echo "  - HDL: 45 mg/dL (normal: >40)"
echo "  - LDL: 110 mg/dL (normal: <130)"
echo "  - Triglycerides: 150 mg/dL (normal: <150)"
echo ""
echo "All values are within normal limits."
echo ""