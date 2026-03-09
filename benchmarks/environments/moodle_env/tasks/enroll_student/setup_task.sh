#!/bin/bash
# Setup script for Enroll Student task

echo "=== Setting up Enroll Student Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get user and course info
echo "Looking up user and course..."
USER_DATA=$(get_user_by_username "epatel" 2>/dev/null)
COURSE_DATA=$(get_course_by_shortname "BIO101" 2>/dev/null)

if [ -n "$USER_DATA" ]; then
    USER_ID=$(echo "$USER_DATA" | cut -f1)
    echo "User epatel found: ID=$USER_ID"
    echo "$USER_ID" > /tmp/target_user_id
else
    echo "WARNING: User epatel not found in database"
    echo "0" > /tmp/target_user_id
fi

if [ -n "$COURSE_DATA" ]; then
    COURSE_ID=$(echo "$COURSE_DATA" | cut -f1)
    echo "Course BIO101 found: ID=$COURSE_ID"
    echo "$COURSE_ID" > /tmp/target_course_id
else
    echo "WARNING: Course BIO101 not found in database"
    echo "0" > /tmp/target_course_id
fi

# Record initial enrollment count
COURSE_ID_VAL=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
if [ "$COURSE_ID_VAL" != "0" ]; then
    INITIAL_ENROLLMENT=$(get_enrollment_count "$COURSE_ID_VAL" 2>/dev/null || echo "0")
else
    INITIAL_ENROLLMENT="0"
fi
echo "$INITIAL_ENROLLMENT" > /tmp/initial_enrollment_count
echo "Initial enrollment count for BIO101: $INITIAL_ENROLLMENT"

# Check if user is already enrolled
USER_ID_VAL=$(cat /tmp/target_user_id 2>/dev/null || echo "0")
if [ "$USER_ID_VAL" != "0" ] && [ "$COURSE_ID_VAL" != "0" ]; then
    if is_user_enrolled "$USER_ID_VAL" "$COURSE_ID_VAL"; then
        echo "NOTE: User epatel is ALREADY enrolled in BIO101"
        echo "true" > /tmp/was_already_enrolled
    else
        echo "User epatel is NOT yet enrolled in BIO101"
        echo "false" > /tmp/was_already_enrolled
    fi
fi

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

echo "=== Enroll Student Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to Moodle as admin"
echo "     - Username: admin"
echo "     - Password: Admin1234!"
echo ""
echo "  2. Navigate to the course 'Introduction to Biology' (BIO101)"
echo ""
echo "  3. Go to Participants"
echo ""
echo "  4. Click 'Enrol users'"
echo ""
echo "  5. Search for and select user 'Emily Patel' (epatel)"
echo ""
echo "  6. Set role to 'Student' and confirm enrollment"
echo ""
