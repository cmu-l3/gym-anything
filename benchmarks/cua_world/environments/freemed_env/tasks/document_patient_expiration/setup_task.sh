#!/bin/bash
# Setup task: document_patient_expiration

echo "=== Setting up document_patient_expiration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure patient Robert Miller exists in the database
PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Robert' AND ptlname='Miller' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_ID" ]; then
    echo "Inserting patient Robert Miller..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Robert', 'Miller', '1945-06-12', '1')" 2>/dev/null
    PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Robert' AND ptlname='Miller' LIMIT 1" 2>/dev/null)
fi

echo "Target Patient ID: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/target_patient_id.txt

# Clean up any pre-existing deceased notes for this patient to ensure a fresh state
freemed_query "DELETE FROM pnotes WHERE patient=$PATIENT_ID AND pnotestext LIKE '%DECEASED%'" 2>/dev/null || true
freemed_query "DELETE FROM annotation WHERE patient=$PATIENT_ID AND annotation LIKE '%DECEASED%'" 2>/dev/null || true

# Ensure Firefox is running and navigating to FreeMED
ensure_firefox_running "http://localhost/freemed/"

# Maximize and focus the browser window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take an initial screenshot to prove task starting state
take_screenshot /tmp/task_initial.png

echo ""
echo "=== document_patient_expiration task setup complete ==="
echo "Task: Mark Robert Miller as deceased (DOD: 2026-03-08)"
echo "FreeMED URL: http://localhost/freemed/"
echo "Login: admin / admin"
echo ""