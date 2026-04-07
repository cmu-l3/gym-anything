#!/bin/bash
# Setup script for Record Vital Signs task

echo "=== Setting up Record Vital Signs Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start timestamp (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient $PATIENT_NAME not found in database!"
    echo "Attempting to check all patients..."
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial vital signs count for this patient (for anti-gaming detection)
echo "Recording initial vital signs count..."
INITIAL_VITALS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_vitals fv JOIN forms f ON f.form_id = fv.id AND f.formdir = 'vitals' WHERE fv.pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_VITALS_COUNT" > /tmp/initial_vitals_count.txt
echo "Initial vitals count for patient: $INITIAL_VITALS_COUNT"

# Record initial encounter count for this patient
INITIAL_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_ENCOUNTER_COUNT" > /tmp/initial_encounter_count.txt
echo "Initial encounter count for patient: $INITIAL_ENCOUNTER_COUNT"

# Ensure Firefox is running and focused on OpenEMR
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

# Dismiss any dialogs by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for audit trail
take_screenshot /tmp/task_initial.png
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Record Vital Signs Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo "Medical History: Hypertension (controlled)"
echo ""
echo "Task: Record the following vital signs within a new encounter:"
echo "  - Blood Pressure: 128/82 mmHg"
echo "  - Pulse: 76 bpm"
echo "  - Temperature: 98.4 °F"
echo "  - Respiratory Rate: 16 breaths/min"
echo "  - Oxygen Saturation: 98%"
echo "  - Weight: 185 lbs"
echo "  - Height: 70 inches"
echo ""
echo "Steps:"
echo "  1. Log in (admin/pass)"
echo "  2. Search for 'Jayson Fadel'"
echo "  3. Open patient chart"
echo "  4. Create new encounter (Wellness Visit)"
echo "  5. Add Vitals form and enter values"
echo "  6. Save"
echo ""