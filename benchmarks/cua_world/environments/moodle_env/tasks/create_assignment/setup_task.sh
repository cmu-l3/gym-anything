#!/bin/bash
# Setup script for Create Assignment task

echo "=== Setting up Create Assignment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get course info
echo "Looking up course BIO101..."
COURSE_DATA=$(get_course_by_shortname "BIO101" 2>/dev/null)

if [ -n "$COURSE_DATA" ]; then
    COURSE_ID=$(echo "$COURSE_DATA" | cut -f1)
    echo "Course BIO101 found: ID=$COURSE_ID"
    echo "$COURSE_ID" > /tmp/target_course_id
else
    echo "WARNING: Course BIO101 not found in database"
    echo "0" > /tmp/target_course_id
fi

# Record initial assignment count for the course
COURSE_ID_VAL=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
if [ "$COURSE_ID_VAL" != "0" ]; then
    INITIAL_ASSIGNMENT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_assign WHERE course=$COURSE_ID_VAL" 2>/dev/null || echo "0")
else
    INITIAL_ASSIGNMENT_COUNT="0"
fi
echo "$INITIAL_ASSIGNMENT_COUNT" > /tmp/initial_assignment_count
echo "Initial assignment count for BIO101: $INITIAL_ASSIGNMENT_COUNT"

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

echo "=== Create Assignment Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to Moodle as admin"
echo "     - Username: admin"
echo "     - Password: Admin1234!"
echo ""
echo "  2. Navigate to the course 'Introduction to Biology' (BIO101)"
echo ""
echo "  3. Turn editing on (gear icon or Edit mode toggle)"
echo ""
echo "  4. Add an activity: Assignment"
echo "     - Name: Lab Report: Cell Biology"
echo "     - Description: Write a 2-page lab report on cell structures"
echo "       observed under the microscope. Include diagrams and observations."
echo "     - Submission type: Online text"
echo "     - Due date: any future date"
echo ""
echo "  5. Save and return to course"
echo ""
