#!/bin/bash
echo "=== Setting up create_clinical_encounter task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Ensure patient Elena Vasquez exists
EXISTS=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Elena' AND ptlname='Vasquez'" 2>/dev/null || echo "0")
if [ "$EXISTS" -eq 0 ]; then
    echo "Inserting synthetic patient Elena Vasquez..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Elena', 'Vasquez', '1966-08-22', 2)" 2>/dev/null || true
fi

# Wait for FreeMED web interface to be responsive
echo "Waiting for FreeMED..."
for i in {1..30}; do
    if curl -s http://localhost/freemed/ > /dev/null; then
        break
    fi
    sleep 1
done

# Start Firefox and navigate to FreeMED
echo "Launching Firefox..."
ensure_firefox_running "http://localhost/freemed/"

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="