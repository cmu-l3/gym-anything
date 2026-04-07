#!/bin/bash
# Setup script for Patient Chart Review Task

echo "=== Setting up Patient Chart Review Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=11
PATIENT_NAME="Mariana Hane"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB, sex, street, city, state, postal_code FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found:"
echo "$PATIENT_CHECK"

# Collect ground truth data for verification
echo ""
echo "Collecting ground truth data..."

# Get medical problems
PROBLEMS=$(openemr_query "SELECT id, title, diagnosis, begdate FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem'" 2>/dev/null)
echo "Medical problems: $PROBLEMS"
PROBLEM_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem'" 2>/dev/null || echo "0")
echo "$PROBLEM_COUNT" > /tmp/patient_problem_count
echo "Problem count: $PROBLEM_COUNT"

# Get medications
MEDICATIONS=$(openemr_query "SELECT id, drug, dosage FROM prescriptions WHERE patient_id=$PATIENT_PID AND active=1" 2>/dev/null)
echo "Medications: $MEDICATIONS"
MED_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID AND active=1" 2>/dev/null || echo "0")
echo "$MED_COUNT" > /tmp/patient_med_count
echo "Medication count: $MED_COUNT"

# Get allergies
ALLERGIES=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND type='allergy'" 2>/dev/null)
echo "Allergies: $ALLERGIES"

# Get recent encounters
ENCOUNTERS=$(openemr_query "SELECT id, date, reason FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY date DESC LIMIT 5" 2>/dev/null)
echo "Recent encounters: $ENCOUNTERS"
ENC_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$ENC_COUNT" > /tmp/patient_enc_count
echo "Encounter count: $ENC_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
date +%Y-%m-%d > /tmp/task_start_date
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Clean up any pre-existing summary file (adversarial prevention)
rm -f /home/ga/Desktop/patient_summary.txt 2>/dev/null || true
echo "Removed any pre-existing summary file"

# Ensure Desktop directory exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved to /tmp/task_start_screenshot.png"

echo ""
echo "=== Patient Chart Review Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Task: Review chart and create summary at /home/ga/Desktop/patient_summary.txt"
echo ""
echo "Summary must include:"
echo "  - Patient name: Mariana Hane"
echo "  - DOB: 1978-06-24"
echo "  - Medical problems (at least 1)"
echo "  - Medications (if any)"
echo "  - File must be at least 500 characters"
echo ""
