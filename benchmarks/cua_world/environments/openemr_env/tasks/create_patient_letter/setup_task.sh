#!/bin/bash
# Setup script for Create Patient Letter task

echo "=== Setting up Create Patient Letter Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
TASK_START=$(cat /tmp/task_start_time.txt)
echo "Task start timestamp: $TASK_START"

# Verify patient exists
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial document count for patient
echo "Recording initial document count..."
INITIAL_DOC_COUNT=$(openemr_query "SELECT COUNT(*) FROM documents WHERE foreign_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_DOC_COUNT" > /tmp/initial_doc_count.txt
echo "Initial document count for patient $PATIENT_PID: $INITIAL_DOC_COUNT"

# Record initial pnotes count for patient (letters may be stored here)
INITIAL_PNOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_PNOTES_COUNT" > /tmp/initial_pnotes_count.txt
echo "Initial pnotes count for patient $PATIENT_PID: $INITIAL_PNOTES_COUNT"

# Record initial onotes count (office notes - another possible storage)
INITIAL_ONOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM onotes" 2>/dev/null || echo "0")
echo "$INITIAL_ONOTES_COUNT" > /tmp/initial_onotes_count.txt
echo "Initial onotes count: $INITIAL_ONOTES_COUNT"

# Record initial form_dictation count
INITIAL_DICTATION_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_dictation" 2>/dev/null || echo "0")
echo "$INITIAL_DICTATION_COUNT" > /tmp/initial_dictation_count.txt
echo "Initial form_dictation count: $INITIAL_DICTATION_COUNT"

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

# Click to ensure focus
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5

# Focus Firefox again
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Create Patient Letter Task Setup Complete ==="
echo ""
echo "TASK: Create a lab results notification letter"
echo "================================================"
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (Username: admin, Password: pass)"
echo "  2. Search for patient Jayson Fadel using Patient > Finder"
echo "  3. Open the patient's chart"
echo "  4. Navigate to letter feature (Miscellaneous > Patient Letter)"
echo "  5. Create a letter with:"
echo "     - Greeting to the patient"
echo "     - Notification that lab results are ready"
echo "     - Request to call (555) 123-4567 to schedule follow-up"
echo "     - Professional closing"
echo "  6. Save the letter to the patient's record"
echo ""