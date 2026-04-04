#!/bin/bash
# Setup script for Create Course task

echo "=== Setting up Create Course Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial course count for verification
echo "Recording initial course count..."
INITIAL_COUNT=$(get_course_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_course_count
echo "Initial course count: $INITIAL_COUNT"

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
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Create Course Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to Moodle as admin"
echo "     - Username: admin"
echo "     - Password: Admin1234!"
echo ""
echo "  2. Navigate to Site Administration > Courses > Add a new course"
echo ""
echo "  3. Fill in the course details:"
echo "     - Course full name: Data Science 101"
echo "     - Course short name: DS101"
echo "     - Course category: Science"
echo ""
echo "  4. Save and display the course"
echo ""
