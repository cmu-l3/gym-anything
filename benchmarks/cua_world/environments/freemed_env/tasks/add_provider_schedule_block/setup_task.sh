#!/bin/bash
echo "=== Setting up add_provider_schedule_block task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure the provider exists
# FreeMED physician table: id, physfname, physlname
PHYS_EXISTS=$(freemed_query "SELECT COUNT(*) FROM physician WHERE physlname='Chen' AND physfname='Sarah'" 2>/dev/null || echo "0")
if [ "$PHYS_EXISTS" -eq "0" ]; then
    echo "Creating provider Dr. Sarah Chen..."
    freemed_query "INSERT INTO physician (physfname, physlname) VALUES ('Sarah', 'Chen')" 2>/dev/null || true
fi

# Get the provider ID
PROVIDER_ID=$(freemed_query "SELECT id FROM physician WHERE physlname='Chen' AND physfname='Sarah' LIMIT 1" 2>/dev/null)
echo "Provider ID: $PROVIDER_ID"
echo "$PROVIDER_ID" > /tmp/target_provider_id.txt

# Delete any existing scheduler records for this provider on the target date to ensure a clean slate
freemed_query "DELETE FROM scheduler WHERE calphysician=$PROVIDER_ID AND caldateof='2026-03-20'" 2>/dev/null || true

# Record initial count of appointments/blocks
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM scheduler" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Start FreeMED in Firefox
ensure_firefox_running "http://localhost/freemed/"

# Maximize and focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="