#!/bin/bash
# Setup script for add_vaccine_dictionary_entry task

echo "=== Setting up Add Vaccine Dictionary Entry task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create initial database dump for schema-agnostic state diffing.
# Using --skip-extended-insert creates one INSERT statement per row,
# which makes text-based diffing reliable without knowing exact table schemas.
echo "Creating initial database dump..."
mysqldump -u freemed -pfreemed freemed --no-create-info --skip-extended-insert 2>/dev/null > /tmp/freemed_initial.sql

# Ensure Firefox is running and focused on FreeMED
echo "Ensuring Firefox is running..."
ensure_firefox_running "http://localhost/freemed/"

# Wait for Firefox window and maximize it
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Clean up any potential previous user history to establish a clean baseline for anti-gaming
rm -f /home/ga/.bash_history
rm -f /home/ga/.mysql_history

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to FreeMED (admin / admin)"
echo "  2. Navigate to the global immunization/vaccine dictionary (Support Data)"
echo "  3. Add 'RSV vaccine, adjuvanted' with CVX code '212'"
echo ""