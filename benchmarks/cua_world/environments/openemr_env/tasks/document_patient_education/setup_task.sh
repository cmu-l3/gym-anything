#!/bin/bash
# Setup script for Document Patient Education Task

echo "=== Setting up Document Patient Education Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient information
PATIENT_PID=5
PATIENT_FNAME="Jacinto"
PATIENT_LNAME="Kiehn"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists and has diabetes
echo "Verifying patient $PATIENT_FNAME $PATIENT_LNAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Verify diabetes diagnosis exists for this patient
echo "Verifying diabetes diagnosis..."
DIABETES_CHECK=$(openemr_query "SELECT id, title, diagnosis FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND (title LIKE '%Diabetes%' OR diagnosis LIKE '%44054006%')" 2>/dev/null)
if [ -z "$DIABETES_CHECK" ]; then
    echo "WARNING: Diabetes diagnosis not found for patient (task may still proceed)"
else
    echo "Diabetes confirmed: $DIABETES_CHECK"
fi

# Record initial counts for verification
echo "Recording initial state counts..."

# Count forms for this patient
INITIAL_FORM_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORM_COUNT" > /tmp/initial_form_count.txt
echo "Initial form count: $INITIAL_FORM_COUNT"

# Count patient notes for this patient
INITIAL_PNOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_PNOTES_COUNT" > /tmp/initial_pnotes_count.txt
echo "Initial patient notes count: $INITIAL_PNOTES_COUNT"

# Count encounters for this patient
INITIAL_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTER_COUNT" > /tmp/initial_encounter_count.txt
echo "Initial encounter count: $INITIAL_ENCOUNTER_COUNT"

# Get latest form ID and pnotes ID to identify new entries
LATEST_FORM_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$LATEST_FORM_ID" > /tmp/latest_form_id.txt

LATEST_PNOTES_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$LATEST_PNOTES_ID" > /tmp/latest_pnotes_id.txt

LATEST_ENCOUNTER_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$LATEST_ENCOUNTER_ID" > /tmp/latest_encounter_id.txt

echo "Latest IDs - Forms: $LATEST_FORM_ID, Notes: $LATEST_PNOTES_ID, Encounters: $LATEST_ENCOUNTER_ID"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill any existing Firefox to start fresh
pkill -f firefox 2>/dev/null || true
sleep 2

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

# Take initial screenshot for audit/verification
sleep 2
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Document Patient Education Task Setup Complete ==="
echo ""
echo "TASK: Document Patient Education"
echo "================================"
echo ""
echo "Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "Condition: Type 2 Diabetes Mellitus"
echo ""
echo "Instructions:"
echo "1. Log in to OpenEMR (Username: admin, Password: pass)"
echo "2. Search for and select patient $PATIENT_FNAME $PATIENT_LNAME"
echo "3. Create a new encounter or open today's encounter"
echo "4. Document patient education about diabetic diet counseling"
echo "5. Save the documentation"
echo ""
echo "Education to document:"
echo "  - Topic: Diabetic diet and nutrition counseling"
echo "  - Method: Verbal counseling with written handout"
echo "  - Notes: Carbohydrate counting, meal timing, glycemic index"
echo ""