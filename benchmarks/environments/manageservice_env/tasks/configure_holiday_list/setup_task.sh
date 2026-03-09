#!/bin/bash
set -e
echo "=== Setting up configure_holiday_list task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for SDP install and start service
ensure_sdp_running

# Clear mandatory password change if set
clear_mandatory_password_change

# Record initial holiday list count for anti-gaming comparison
# Using multiple potential table names to be robust across SDP versions
INITIAL_HOLIDAY_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM holidaylist;" 2>/dev/null || \
    sdp_db_exec "SELECT COUNT(*) FROM holiday_list;" 2>/dev/null || echo "0")
echo "$INITIAL_HOLIDAY_COUNT" > /tmp/initial_holiday_list_count.txt

# Ensure Firefox is open on SDP Login or Home
echo "Launching Firefox on ServiceDesk Plus..."
if ! pgrep -f firefox > /dev/null; then
    ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "firefox|ServiceDesk|ManageEngine|Login"; then
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Attempt auto-login script if available (helper provided in some envs)
if [ -f "/workspace/scripts/auto_login.py" ]; then
    python3 /workspace/scripts/auto_login.py 2>/dev/null || true
fi

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Agent should navigate to Admin > Holiday List and create the holiday list."