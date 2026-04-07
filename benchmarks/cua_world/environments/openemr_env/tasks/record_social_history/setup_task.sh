#!/bin/bash
# Setup script for Record Social History Task

echo "=== Setting up Record Social History Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

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

# Record initial history_data state for this patient
echo "Recording initial social history state..."
INITIAL_HISTORY=$(openemr_query "SELECT id, tobacco, coffee, alcohol, sleep_patterns, exercise_patterns, hazardous_activities, recreational_drugs, occupation FROM history_data WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

# Save initial state to JSON
python3 << PYEOF
import json
import time

initial_state = {
    "timestamp": $(date +%s),
    "patient_pid": $PATIENT_PID,
    "patient_name": "$PATIENT_NAME",
    "initial_history_raw": """$INITIAL_HISTORY""",
    "history_exists": len("""$INITIAL_HISTORY""".strip()) > 0
}

# Parse initial history if it exists
if initial_state["history_exists"]:
    fields = """$INITIAL_HISTORY""".strip().split('\t')
    if len(fields) >= 9:
        initial_state["initial_history"] = {
            "id": fields[0] if fields[0] else None,
            "tobacco": fields[1] if len(fields) > 1 else None,
            "coffee": fields[2] if len(fields) > 2 else None,
            "alcohol": fields[3] if len(fields) > 3 else None,
            "sleep_patterns": fields[4] if len(fields) > 4 else None,
            "exercise_patterns": fields[5] if len(fields) > 5 else None,
            "hazardous_activities": fields[6] if len(fields) > 6 else None,
            "recreational_drugs": fields[7] if len(fields) > 7 else None,
            "occupation": fields[8] if len(fields) > 8 else None
        }
else:
    initial_state["initial_history"] = None

with open('/tmp/initial_history_state.json', 'w') as f:
    json.dump(initial_state, f, indent=2)

print("Initial state saved to /tmp/initial_history_state.json")
PYEOF

# Clear/reset social history fields to ensure clean test state
# This ensures we're testing actual data entry, not just viewing existing data
echo "Clearing existing social history for clean test..."
openemr_query "UPDATE history_data SET tobacco=NULL, coffee=NULL, alcohol=NULL, sleep_patterns=NULL, exercise_patterns=NULL, hazardous_activities=NULL, recreational_drugs=NULL, occupation=NULL WHERE pid=$PATIENT_PID" 2>/dev/null || true

# Verify the clear worked
CLEARED_CHECK=$(openemr_query "SELECT tobacco, alcohol, occupation FROM history_data WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
echo "After clear - history fields: $CLEARED_CHECK"

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

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Record Social History Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NAME (PID: $PATIENT_PID, DOB: 1992-06-30)"
echo ""
echo "Task: Document the following social history:"
echo "  - Smoking Status: Former Smoker"
echo "  - Tobacco Type: Cigarettes"
echo "  - Pack-Years: 8"
echo "  - Quit Date: 2018-06-15"
echo "  - Alcohol: Social drinker, 2-3 drinks/week"
echo "  - Recreational Drugs: None/Denies"
echo "  - Occupation: Software Developer"
echo "  - Exercise: Moderate - walks 30 min daily"
echo ""
echo "Login credentials: admin / pass"
echo ""