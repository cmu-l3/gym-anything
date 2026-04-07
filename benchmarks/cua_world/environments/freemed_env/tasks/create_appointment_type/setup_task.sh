#!/bin/bash
# Setup script for create_appointment_type task

echo "=== Setting up create_appointment_type task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_timestamp

# Schema-agnostic baseline: Dump the database and check for any existing "Telehealth Counseling" records
echo "Recording initial state..."
mysqldump -u freemed -pfreemed freemed --skip-extended-insert > /tmp/initial_dump.sql 2>/dev/null || true
INITIAL_MATCH_COUNT=$(grep -i "Telehealth Counseling" /tmp/initial_dump.sql | wc -l || echo "0")
echo "$INITIAL_MATCH_COUNT" > /tmp/initial_match_count
echo "Initial matches for 'Telehealth Counseling' in database: $INITIAL_MATCH_COUNT"

# Ensure Firefox is running and focused on FreeMED
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window for better agent interaction
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot to document starting state
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Instructions:"
echo "1. Log into FreeMED (admin/admin)"
echo "2. Navigate to Support Data > Appointment Types (or equivalent Scheduling configuration)"
echo "3. Add new type: 'Telehealth Counseling' with duration '45' minutes."