#!/bin/bash
# Setup script for Document HPI Task

echo "=== Setting up Document HPI Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial form count for this patient (to detect new documentation)
echo "Recording initial form counts..."
INITIAL_FORM_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORM_COUNT" > /tmp/initial_form_count.txt
echo "Initial form count for patient: $INITIAL_FORM_COUNT"

# Record initial encounter count
INITIAL_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTER_COUNT" > /tmp/initial_encounter_count.txt
echo "Initial encounter count for patient: $INITIAL_ENCOUNTER_COUNT"

# Record initial SOAP note count (common HPI location)
INITIAL_SOAP_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_soap WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_SOAP_COUNT" > /tmp/initial_soap_count.txt
echo "Initial SOAP note count: $INITIAL_SOAP_COUNT"

# Record initial clinical notes count
INITIAL_CLINICAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_clinical_notes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_CLINICAL_COUNT" > /tmp/initial_clinical_count.txt
echo "Initial clinical notes count: $INITIAL_CLINICAL_COUNT"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window to appear
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
sleep 2
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Document HPI Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo ""
echo "Clinical Scenario:"
echo "  Patient presents with lower back pain that started 5 days ago"
echo "  after lifting heavy boxes. Pain is dull/aching, 6/10 severity,"
echo "  worse with bending and in morning, improved with rest/ibuprofen."
echo "  Denies leg symptoms, numbness, or bowel/bladder changes."
echo ""
echo "Task: Document a comprehensive HPI with at least 4 elements."
echo ""