#!/bin/bash
# Setup script for Document Fall Risk Assessment Task

echo "=== Setting up Fall Risk Assessment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=4
PATIENT_NAME="Lavon Kuvalis"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial form/note counts for this patient
echo "Recording initial documentation counts..."
INITIAL_FORMS=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID AND deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS" > /tmp/initial_form_count.txt
echo "Initial form count for patient: $INITIAL_FORMS"

INITIAL_NOTES=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID AND deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_NOTES" > /tmp/initial_note_count.txt
echo "Initial note count for patient: $INITIAL_NOTES"

INITIAL_ENCOUNTERS=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTERS" > /tmp/initial_encounter_count.txt
echo "Initial encounter count for patient: $INITIAL_ENCOUNTERS"

# Record initial form IDs to detect new entries
INITIAL_FORM_IDS=$(openemr_query "SELECT MAX(id) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORM_IDS" > /tmp/initial_max_form_id.txt

INITIAL_NOTE_IDS=$(openemr_query "SELECT MAX(id) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_NOTE_IDS" > /tmp/initial_max_note_id.txt

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

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Fall Risk Assessment Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1929-07-23)"
echo "Age: 95 years old"
echo ""
echo "Task: Document a fall risk assessment using the Morse Fall Scale"
echo ""
echo "Assessment findings to document:"
echo "  - History of falling: Yes (25 pts)"
echo "  - Secondary diagnosis: Yes (15 pts)"
echo "  - Ambulatory aid: Walker (15 pts)"
echo "  - IV/Heparin: No (0 pts)"
echo "  - Gait: Impaired (20 pts)"
echo "  - Mental status: Forgets limitations (15 pts)"
echo "  - TOTAL: 90 (High Risk)"
echo ""
echo "Include intervention: Fall precautions protocol, patient education"
echo ""