#!/bin/bash
echo "=== Setting up add_cpt_code task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any pre-existing CPT code 99214 to ensure a clean task state
freemed_query "DELETE FROM cpt WHERE cptcode = '99214'" 2>/dev/null || true

# Record initial CPT code count for anti-gaming verification
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM cpt" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_cpt_count.txt
echo "Initial CPT count: $INITIAL_COUNT"

# Ensure Firefox is running and logged in
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_cpt_start.png

echo ""
echo "=== add_cpt_code task setup complete ==="
echo "Task: Add CPT Code 99214 to FreeMED database"
echo "Login: admin / admin"
echo ""