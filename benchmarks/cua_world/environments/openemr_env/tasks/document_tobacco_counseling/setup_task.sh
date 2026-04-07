#!/bin/bash
# Setup script for Document Tobacco Cessation Counseling Task

echo "=== Setting up Document Tobacco Counseling Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=2
PATIENT_NAME="Edgar Parker Sr."

# Record task start timestamp for anti-gaming
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

# Check for smoking history in history_data
echo "Checking smoking history..."
SMOKING_HISTORY=$(openemr_query "SELECT tobacco FROM history_data WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "Smoking history: $SMOKING_HISTORY"

# Record initial encounter count for this patient
echo "Recording initial encounter count..."
INITIAL_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTER_COUNT" > /tmp/initial_encounter_count
echo "Initial encounter count: $INITIAL_ENCOUNTER_COUNT"

# Record initial forms count for this patient
INITIAL_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS_COUNT" > /tmp/initial_forms_count
echo "Initial forms count: $INITIAL_FORMS_COUNT"

# Record most recent form ID to detect new forms
LAST_FORM_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$LAST_FORM_ID" > /tmp/last_form_id
echo "Last form ID: $LAST_FORM_ID"

# Record most recent encounter ID
LAST_ENCOUNTER_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$LAST_ENCOUNTER_ID" > /tmp/last_encounter_id
echo "Last encounter ID: $LAST_ENCOUNTER_ID"

# Today's date for checking encounter date validity
TODAY=$(date +%Y-%m-%d)
echo "$TODAY" > /tmp/task_date
echo "Task date: $TODAY"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill any existing Firefox instances for clean start
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

# Click in center of screen to ensure focus
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5

# Focus Firefox again
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Document Tobacco Counseling Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1968-06-24)"
echo "Task: Document tobacco cessation counseling intervention"
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""
echo "Required documentation elements:"
echo "  - Intervention type: Tobacco cessation counseling"
echo "  - Counseling method: Brief motivational intervention"  
echo "  - Time spent: 10 minutes"
echo "  - Topics: Health risks, quit date planning, NRT options"
echo "  - Patient response: Interested in quitting"
echo "  - Follow-up: Nicotine patch Rx, 2-week callback"
echo ""