#!/bin/bash
# Setup script for Enter Lab Results task

echo "=== Setting up Enter Lab Results Task ==="

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

# Verify hypertension condition exists (clinical context)
echo "Verifying hypertension diagnosis..."
HTN_CHECK=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%Hypertension%' OR diagnosis LIKE '%59621000%')" 2>/dev/null)
if [ -z "$HTN_CHECK" ]; then
    echo "Note: Hypertension diagnosis not explicitly found"
else
    echo "Hypertension confirmed: $HTN_CHECK"
fi

# Record initial procedure order count for this patient
echo "Recording initial procedure counts..."
INITIAL_ORDER_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_procedure_order_count
echo "Initial procedure order count for patient: $INITIAL_ORDER_COUNT"

# Record initial procedure result count (across all patients for broader check)
INITIAL_RESULT_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_result" 2>/dev/null || echo "0")
echo "$INITIAL_RESULT_COUNT" > /tmp/initial_procedure_result_count
echo "Initial total procedure result count: $INITIAL_RESULT_COUNT"

# Record current date for validation
date +%Y-%m-%d > /tmp/task_date
echo "Task date: $(cat /tmp/task_date)"

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
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Enter Lab Results Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Condition: Hypertension (on antihypertensive therapy)"
echo ""
echo "Lab Results to Enter (Basic Metabolic Panel):"
echo "  - Glucose: 108 mg/dL"
echo "  - BUN: 22 mg/dL"
echo "  - Creatinine: 1.2 mg/dL"
echo "  - Sodium: 139 mEq/L"
echo "  - Potassium: 4.5 mEq/L"
echo "  - Chloride: 103 mEq/L"
echo "  - CO2: 25 mEq/L"
echo ""
echo "Navigate to: Patient Chart > Procedures > Enter Results"
echo ""