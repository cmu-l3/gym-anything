#!/bin/bash
# Setup task: record_patient_lab_result
# Patient: Maria Santos

echo "=== Setting up record_patient_lab_result task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure Maria Santos exists in the system
PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_ID" ]; then
    echo "Patient Maria Santos not found, creating record..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptsex, ptdob) VALUES ('Maria', 'Santos', '2', '1980-05-14');" 2>/dev/null
    PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos' LIMIT 1" 2>/dev/null)
fi

echo "Target patient ID: $PATIENT_ID"

# Clean up any potential previous artifacts for this specific accession number
# Since we don't know exactly which table the agent will use (could be notes, measurements, etc.),
# we will rely on the uniqueness of the Accession Number.
# But just in case, we can try to clean the most common ones:
freemed_query "DELETE FROM pnotes WHERE pnotetext LIKE '%ACC-88492-LP%'" 2>/dev/null || true
freemed_query "DELETE FROM patient_measurements WHERE notes LIKE '%ACC-88492-LP%'" 2>/dev/null || true

# Start Firefox and navigate to FreeMED
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial state screenshot
take_screenshot /tmp/task_lab_start.png

echo ""
echo "=== record_patient_lab_result task setup complete ==="
echo "Task: Record Lipid Panel for Maria Santos"
echo "Accession: ACC-88492-LP"
echo "Login: admin / admin"
echo ""