#!/bin/bash
echo "=== Setting up add_user_account task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the target user does NOT already exist for a clean state
freemed_query "DELETE FROM user WHERE username='smitchell';" 2>/dev/null || true
echo "Ensured smitchell does not pre-exist"

# Record initial user count (for anti-gaming verification)
INITIAL_USER_COUNT=$(freemed_query "SELECT COUNT(*) FROM user" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt
echo "Initial user count: $INITIAL_USER_COUNT"

# Ensure services are running
systemctl start mysql 2>/dev/null || service mysql start
systemctl start apache2 2>/dev/null || service apache2 start
sleep 2

# Ensure Firefox is running and at the login/dashboard page
ensure_firefox_running "http://localhost/freemed/"
sleep 5

# Maximize and focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Agent should create a new user account for Sarah Mitchell (smitchell) via the FreeMED UI."