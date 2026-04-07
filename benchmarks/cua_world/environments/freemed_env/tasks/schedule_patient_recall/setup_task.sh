#!/bin/bash
# Setup task: schedule_patient_recall
# Ensures the target patient exists and the environment is clean

echo "=== Setting up schedule_patient_recall task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure target patient Thomas Vance exists in the database
echo "Checking/creating patient Thomas Vance..."
freemed_query "INSERT IGNORE INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Thomas', 'Vance', '1970-05-15', 1);" 2>/dev/null || true

# Retrieve the patient ID to verify creation
PT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Thomas' AND ptlname='Vance' LIMIT 1" 2>/dev/null)
echo "Patient Thomas Vance ID: $PT_ID"

if [ -z "$PT_ID" ]; then
    echo "ERROR: Failed to create or find patient Thomas Vance!"
    exit 1
fi

# Clean up any existing recalls/reminders for this patient to ensure a clean state
# We search common FreeMED recall tables to prevent gaming
freemed_query "DELETE FROM pcall WHERE pcallpatient='$PT_ID'" 2>/dev/null || true
freemed_query "DELETE FROM patient_reminders WHERE patient='$PT_ID'" 2>/dev/null || true
freemed_query "DELETE FROM messages WHERE patient='$PT_ID'" 2>/dev/null || true

# Start Firefox and navigate to FreeMED
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Let UI settle
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo ""
echo "=== schedule_patient_recall task setup complete ==="
echo "Target Patient: Thomas Vance (ID: $PT_ID)"
echo "Task: Create 3-year recall for Colonoscopy"
echo "Login: admin / admin"
echo ""