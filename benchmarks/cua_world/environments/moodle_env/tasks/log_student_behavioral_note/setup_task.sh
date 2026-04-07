#!/bin/bash
# Setup script for Log Student Behavioral Note task

echo "=== Setting up Log Student Note Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Verify target user and course exist
echo "Verifying prerequisites..."

# Get User ID for dlee
USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='dlee' AND deleted=0" | tr -d '[:space:]')
if [ -z "$USER_ID" ]; then
    echo "ERROR: User 'dlee' not found. Creating..."
    # Fallback creation if needed (should exist from env setup)
    # But for now assuming env is correct as per spec
    exit 1
fi
echo "Target User ID: $USER_ID"
echo "$USER_ID" > /tmp/target_user_id

# Get Course ID for HIST201
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='HIST201'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: Course 'HIST201' not found."
    exit 1
fi
echo "Target Course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/target_course_id

# Ensure student is enrolled (prerequisite for course-level notes usually)
if ! is_user_enrolled "$USER_ID" "$COURSE_ID"; then
    echo "Enrolling dlee in HIST201..."
    # Manual SQL enrollment if needed, but setup_moodle.sh usually handles this
    # For this task, we assume the environment is standard.
    echo "WARNING: User might not be enrolled. Proceeding anyway."
fi

# Record initial note count for this user in this course
# publishstate: 'personal', 'course', 'site'
INITIAL_NOTE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_post WHERE userid=$USER_ID AND courseid=$COURSE_ID AND module='notes'" 2>/dev/null || echo "0")
# Note: Moodle notes are stored in mdl_post in newer versions or mdl_note in older. 
# Moodle 4.x usually uses mdl_note table.
INITIAL_NOTE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_note WHERE userid=$USER_ID AND courseid=$COURSE_ID" 2>/dev/null)
echo "${INITIAL_NOTE_COUNT:-0}" > /tmp/initial_note_count
echo "Initial note count: ${INITIAL_NOTE_COUNT:-0}"

# Ensure Firefox is running
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
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="