#!/bin/bash
echo "=== Setting up generate_patient_summary task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and create a reference file for timestamp comparisons
date +%s > /tmp/task_start_timestamp
touch /tmp/task_start_marker

# Ensure target patient Maria Santos exists in the database
PATIENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Maria' AND ptlname='Santos'" 2>/dev/null || echo "0")

if [ "$PATIENT_COUNT" -eq 0 ]; then
    echo "Patient Maria Santos not found. Inserting default clinical record..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptsex, ptdob) VALUES ('Maria', 'Santos', '2', '1980-05-15');" 2>/dev/null || true
    # Add a dummy vitals record so the summary isn't completely empty
    PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos' LIMIT 1" 2>/dev/null)
    if [ -n "$PATIENT_ID" ]; then
        freemed_query "INSERT INTO vitals (patient, dateof, weight, height, systolic, diastolic) VALUES ($PATIENT_ID, NOW(), '150', '65', '120', '80');" 2>/dev/null || true
    fi
else
    echo "Patient Maria Santos already exists."
fi

# Clear out any old downloaded files to ensure we only detect new downloads
rm -f /home/ga/Downloads/*.pdf 2>/dev/null || true
rm -f /home/ga/Downloads/*.xml 2>/dev/null || true
rm -f /home/ga/Downloads/*.html 2>/dev/null || true

# Launch FreeMED in Firefox
ensure_firefox_running "http://localhost/freemed/"

# Maximize and focus the browser
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take an initial screenshot
take_screenshot /tmp/task_initial_state.png

echo ""
echo "=== Setup complete ==="
echo "Task: Generate clinical summary / print chart for Maria Santos"