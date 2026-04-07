#!/bin/bash
echo "=== Setting up add_insurance_company task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure MySQL and Apache are running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
systemctl start apache2 2>/dev/null || service apache2 start 2>/dev/null || true
sleep 2

# Remove any pre-existing BCBS record to ensure clean state
freemed_query "DELETE FROM insco WHERE insconame LIKE '%Blue Cross%';" 2>/dev/null || true

# Record initial insco count
INITIAL_INSCO_COUNT=$(freemed_query "SELECT COUNT(*) FROM insco;" 2>/dev/null || echo "0")
echo "$INITIAL_INSCO_COUNT" > /tmp/initial_insco_count.txt
echo "Initial insurance company count: $INITIAL_INSCO_COUNT"

# Start Firefox with FreeMED
ensure_firefox_running "http://localhost/freemed/"

# Wait for Firefox window and focus
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any dialogs
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        xdotool key Escape 2>/dev/null || true
    sleep 1
fi

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "FreeMED URL: http://localhost/freemed/"
echo "Login: admin / admin"
echo "Task: Add insurance company 'Blue Cross Blue Shield of Massachusetts'"