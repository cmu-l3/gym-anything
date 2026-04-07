#!/bin/bash
# Setup script for Create Onboarding User Tour task

echo "=== Setting up User Tour Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial tour count
echo "Recording initial user tour count..."
INITIAL_TOUR_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_tool_usertours_tours" 2>/dev/null || echo "0")
echo "$INITIAL_TOUR_COUNT" > /tmp/initial_tour_count
echo "Initial tour count: $INITIAL_TOUR_COUNT"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for and focus Firefox
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Record start time
date +%s > /tmp/task_start_timestamp

echo "=== Setup Complete ==="