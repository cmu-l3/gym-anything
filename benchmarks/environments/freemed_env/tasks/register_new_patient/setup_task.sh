#!/bin/bash
# Setup task: register_new_patient
# Garfield Lebsack - Synthea patient 21 (not pre-loaded into FreeMED)

echo "=== Setting up register_new_patient task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Ensure Garfield Lebsack does NOT exist (task is to create him)
EXISTING=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Garfield' AND ptlname='Lebsack'" 2>/dev/null || echo "0")
if [ "${EXISTING:-0}" -gt 0 ]; then
    echo "Removing pre-existing Garfield Lebsack record to ensure clean task state..."
    freemed_query "DELETE FROM patient WHERE ptfname='Garfield' AND ptlname='Lebsack'" 2>/dev/null || true
fi

# Record initial patient count
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM patient" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_patient_count
echo "Initial patient count: $INITIAL_COUNT"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/freemed/ 2>/dev/null)
echo "FreeMED HTTP status: $HTTP_CODE"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_register_start.png

echo ""
echo "=== register_new_patient task setup complete ==="
echo "Task: Register Garfield Lebsack (DOB: 1962-05-16, Male)"
echo "Addr: 393 Mertz Crossing Apt 28, Ludlow, MA 01056"
echo "Phone: 617-555-4701, Email: garfield.lebsack@synthea.test"
echo "FreeMED URL: http://localhost/freemed/"
echo "Login: admin / admin"
echo ""
