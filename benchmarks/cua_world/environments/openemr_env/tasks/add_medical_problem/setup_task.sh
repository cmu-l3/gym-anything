#!/bin/bash
# Setup script for Add Medical Problem Task

echo "=== Setting up Add Medical Problem Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify patient has existing hypertension (confirms correct patient)
echo "Verifying existing hypertension diagnosis..."
HTN_CHECK=$(openemr_query "SELECT id, title, begdate FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND LOWER(title) LIKE '%hypertension%'" 2>/dev/null)
if [ -n "$HTN_CHECK" ]; then
    echo "Existing hypertension confirmed: $HTN_CHECK"
else
    echo "NOTE: Hypertension diagnosis not found (may have different naming)"
fi

# Record initial problem count for this patient (CRITICAL for anti-gaming)
echo "Recording initial problem count..."
INITIAL_PROBLEM_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem'" 2>/dev/null || echo "0")
echo "$INITIAL_PROBLEM_COUNT" > /tmp/initial_problem_count
echo "Initial problem count for patient: $INITIAL_PROBLEM_COUNT"

# Record list of existing problem IDs (to detect new vs pre-existing)
EXISTING_PROBLEM_IDS=$(openemr_query "SELECT id FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' ORDER BY id" 2>/dev/null || echo "")
echo "$EXISTING_PROBLEM_IDS" > /tmp/existing_problem_ids
echo "Existing problem IDs: $EXISTING_PROBLEM_IDS"

# Check if osteoarthritis already exists (would be cheating if agent does nothing)
EXISTING_OA=$(openemr_query "SELECT id, title FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND LOWER(title) LIKE '%osteoarthritis%'" 2>/dev/null)
if [ -n "$EXISTING_OA" ]; then
    echo "WARNING: Osteoarthritis already exists - this will be flagged in verification"
    echo "$EXISTING_OA" > /tmp/preexisting_osteoarthritis
else
    echo "No pre-existing osteoarthritis found (good - task is valid)"
    echo "" > /tmp/preexisting_osteoarthritis
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
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved to /tmp/task_start_screenshot.png"

echo ""
echo "=== Add Medical Problem Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo "Task: Add 'Osteoarthritis' to the patient's problem list"
echo "Required onset date: 2024-01-15"
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""
echo "Navigation hint: After opening patient chart, look for"
echo "  Issues > Medical Problems, or Medical Problems in left menu"
echo ""