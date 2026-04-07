#!/bin/bash
echo "=== Setting up add_postal_code task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure a clean state by removing the target zip code if it already exists
echo "Cleaning up any existing target data..."
freemed_query "DELETE FROM zipcodes WHERE zip='60523';" 2>/dev/null || true

# Record initial count from the primary table
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM zipcodes" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_zip_count
echo "Initial zip code count: $INITIAL_COUNT"

# Take a full schema-agnostic DB dump for the initial state
echo "Capturing initial database state..."
mysqldump -u freemed -pfreemed freemed > /tmp/initial_dump.sql 2>/dev/null

# Ensure Firefox is running and FreeMED is accessible
echo "Ensuring Firefox is running and on FreeMED login page..."
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window for full UI visibility
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_postal_start.png

echo ""
echo "=== add_postal_code task setup complete ==="
echo "Task: Add Zip Code 60523 (Oak Brook, IL) to FreeMED support data dictionaries."
echo "Login: admin / admin"
echo ""