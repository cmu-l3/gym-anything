#!/bin/bash
# Setup script for Document Family History task

echo "=== Setting up Document Family History Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=4
PATIENT_NAME="Philip Walker"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient Philip Walker (pid=4) not found in database!"
    echo "Checking available patients..."
    openemr_query "SELECT pid, fname, lname FROM patient_data LIMIT 10" 2>/dev/null
    exit 1
fi
echo "Patient verified: $PATIENT_CHECK"

# Record initial state of family history fields for this patient
echo "Recording initial family history state..."
INITIAL_HISTORY=$(openemr_query "SELECT id, relatives_diabetes, relatives_heart_problems, relatives_cancer, date FROM history_data WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

# Also get count of history records
INITIAL_HISTORY_COUNT=$(openemr_query "SELECT COUNT(*) FROM history_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

# Check lists table for family_history type entries
INITIAL_LISTS_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='family_history'" 2>/dev/null || echo "0")

# Save initial state to JSON file
cat > /tmp/initial_family_history_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "patient_pid": $PATIENT_PID,
    "patient_name": "$PATIENT_NAME",
    "initial_history_count": ${INITIAL_HISTORY_COUNT:-0},
    "initial_lists_count": ${INITIAL_LISTS_COUNT:-0},
    "initial_history_data": "$(echo "$INITIAL_HISTORY" | tr '\t' '|' | tr '\n' ' ')"
}
EOF

echo "Initial state saved:"
cat /tmp/initial_family_history_state.json

# Ensure Firefox is running on OpenEMR login page
echo ""
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

# Navigate to login page in case browser is on different page
su - ga -c "DISPLAY=:1 xdotool key ctrl+l" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type '$OPENEMR_URL'" 2>/dev/null || true
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 3

# Take initial screenshot for audit verification
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Document Family History Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 2015-07-04)"
echo ""
echo "Task: Document the following family medical history:"
echo "  - Mother: Type 2 Diabetes Mellitus (diagnosed age 45)"
echo "  - Father: Myocardial Infarction / Heart Attack (age 58)"
echo "  - Maternal Grandmother: Breast Cancer (diagnosed age 62)"
echo ""
echo "Login: admin / pass"
echo ""