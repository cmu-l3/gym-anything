#!/bin/bash
# Setup script for Document PHQ-9 Screening Task

echo "=== Setting up Document PHQ-9 Screening Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (critical for anti-gaming)
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

# Record initial state counts for various tables where PHQ-9 could be documented

# Count patient notes
INITIAL_NOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_NOTES_COUNT" > /tmp/initial_notes_count
echo "Initial patient notes count: $INITIAL_NOTES_COUNT"

# Count forms for this patient
INITIAL_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms f JOIN form_encounter fe ON f.encounter = fe.encounter WHERE fe.pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS_COUNT" > /tmp/initial_forms_count
echo "Initial forms count: $INITIAL_FORMS_COUNT"

# Count encounters
INITIAL_ENCOUNTERS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTERS_COUNT" > /tmp/initial_encounters_count
echo "Initial encounters count: $INITIAL_ENCOUNTERS_COUNT"

# Count clinical notes/observations
INITIAL_OBSERVATIONS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_observation WHERE id IN (SELECT form_id FROM forms WHERE formdir='observation' AND pid=$PATIENT_PID)" 2>/dev/null || echo "0")
echo "$INITIAL_OBSERVATIONS_COUNT" > /tmp/initial_observations_count
echo "Initial observations count: $INITIAL_OBSERVATIONS_COUNT"

# Record any existing PHQ-related entries for comparison
echo "Recording existing PHQ-related entries..."
openemr_query "SELECT id, date, body FROM pnotes WHERE pid=$PATIENT_PID AND (body LIKE '%PHQ%' OR body LIKE '%depression%' OR body LIKE '%screening%')" 2>/dev/null > /tmp/initial_phq_notes || true

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
echo "=== Document PHQ-9 Screening Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID)"
echo "Task: Document PHQ-9 depression screening with score of 8 (mild depression)"
echo ""
echo "PHQ-9 Score Interpretation:"
echo "  0-4:   Minimal/None"
echo "  5-9:   Mild depression (target score: 8)"
echo "  10-14: Moderate depression"
echo "  15-19: Moderately severe depression"
echo "  20-27: Severe depression"
echo ""