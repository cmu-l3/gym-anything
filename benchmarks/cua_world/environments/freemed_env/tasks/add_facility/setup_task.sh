#!/bin/bash
# Setup script for Add Facility task

echo "=== Setting up Add Facility Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state: delete any existing facility matching the task to prevent false positives
echo "Cleaning up any pre-existing matching facilities..."
freemed_query "DELETE FROM facility WHERE facilityname LIKE '%Riverside%' OR name LIKE '%Riverside%'" 2>/dev/null || true

# Record initial facility count
echo "Recording initial facility count..."
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM facility" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_facility_count
echo "Initial facility count: $INITIAL_COUNT"

# Ensure Firefox is running and focused on FreeMED
echo "Ensuring Firefox is running..."
FREEMED_URL="http://localhost/freemed/"

ensure_firefox_running "$FREEMED_URL"

# Focus Firefox window and maximize
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Add Facility Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to FreeMED (admin / admin)"
echo "  2. Navigate to System Configuration / Facilities"
echo "  3. Add new facility: Riverside Family Health Center"
echo "     Address: 2450 River Road, Springfield, IL 62704"
echo "     Phone: 2175550198"
echo "  4. Save the record."
echo ""