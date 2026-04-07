#!/bin/bash
# Setup script for Configure Blind Marking Assignment task

echo "=== Setting up Blind Marking Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial course count for verification
# This helps detect if a NEW course was created vs editing an existing one
echo "Recording initial state..."
INITIAL_COURSE_COUNT=$(get_course_count 2>/dev/null || echo "0")
echo "$INITIAL_COURSE_COUNT" > /tmp/initial_course_count

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running and focused on Moodle
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window for best agent visibility
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="