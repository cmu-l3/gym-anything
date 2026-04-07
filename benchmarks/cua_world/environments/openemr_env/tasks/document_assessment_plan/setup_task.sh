#!/bin/bash
# Setup script for Document Assessment and Plan Task

echo "=== Setting up Document Assessment and Plan Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
TASK_START=$(cat /tmp/task_start_timestamp)
echo "Task start timestamp: $TASK_START"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify hypertension condition exists for clinical context
echo "Verifying hypertension diagnosis..."
HTN_CHECK=$(openemr_query "SELECT id, title, diagnosis FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%Hypertension%' OR title LIKE '%hypertension%' OR diagnosis LIKE '%59621000%')" 2>/dev/null)
if [ -z "$HTN_CHECK" ]; then
    echo "WARNING: Hypertension diagnosis not found for patient"
else
    echo "Hypertension confirmed: $HTN_CHECK"
fi

# Record initial SOAP form count for this patient
echo "Recording initial SOAP form count..."
INITIAL_SOAP_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_soap WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_SOAP_COUNT" > /tmp/initial_soap_count
echo "Initial SOAP form count for patient: $INITIAL_SOAP_COUNT"

# Record initial encounter count for this patient
INITIAL_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTER_COUNT" > /tmp/initial_encounter_count
echo "Initial encounter count for patient: $INITIAL_ENCOUNTER_COUNT"

# Record initial forms count (generic forms table)
INITIAL_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS_COUNT" > /tmp/initial_forms_count
echo "Initial forms count for patient: $INITIAL_FORMS_COUNT"

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
echo "=== Document Assessment and Plan Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Condition: Hypertension (requires A&P documentation)"
echo ""
echo "Task: Document Assessment and Plan for this patient's encounter"
echo "  - Create/access an encounter"
echo "  - Open SOAP note or A&P form"
echo "  - Document assessment of hypertension status"
echo "  - Document treatment plan"
echo "  - Save the documentation"
echo ""