#!/bin/bash
# Setup script for Add Appointment Category task

echo "=== Setting up Add Appointment Category Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Take a pre-task database snapshot to verify the record is NEWLY created during the task
echo "Taking pre-task database snapshot..."
mysqldump -u freemed -pfreemed --skip-extended-insert freemed > /tmp/db_dump_before.sql 2>/dev/null || true

# Check if Firefox is running, if not start it and point to FreeMED
echo "Ensuring Firefox is running and pointing to FreeMED..."
ensure_firefox_running "http://localhost/freemed/"

# Wait for Firefox window and focus/maximize it
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    echo "Focusing and maximizing Firefox window..."
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot of the starting state
take_screenshot /tmp/task_initial.png

echo "=== Add Appointment Category Task Setup Complete ==="
echo ""
echo "Task: Add an appointment category named 'Diabetes Education' with a duration of 45 minutes."
echo "Login: admin / admin"
echo ""