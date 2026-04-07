#!/bin/bash
# Setup script for Export Gradebook CSV task

echo "=== Setting up Export Gradebook CSV Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up any previous attempts
rm -f /home/ga/Documents/BIO101_Grades.csv 2>/dev/null
rm -f /home/ga/Downloads/* 2>/dev/null

# 2. Get Course and User IDs
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found"
    exit 1
fi

USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='jsmith'" | tr -d '[:space:]')
if [ -z "$USER_ID" ]; then
    echo "ERROR: User jsmith not found"
    exit 1
fi

# 3. Create a Grade Item "Lab Safety Quiz" if it doesn't exist
# Check if item exists
ITEM_ID=$(moodle_query "SELECT id FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemname='Lab Safety Quiz' AND itemtype='manual'" | tr -d '[:space:]')

if [ -z "$ITEM_ID" ]; then
    echo "Creating 'Lab Safety Quiz' grade item..."
    # Insert grade item (manual type)
    moodle_query "INSERT INTO mdl_grade_items (courseid, categoryid, itemname, itemtype, iteminfo, idnumber, gradetype, grademax, grademin, timecreated, timemodified) VALUES ($COURSE_ID, NULL, 'Lab Safety Quiz', 'manual', NULL, NULL, 1, 100.00, 0.00, $(date +%s), $(date +%s))"
    ITEM_ID=$(moodle_query "SELECT id FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemname='Lab Safety Quiz'" | tr -d '[:space:]')
fi

# 4. Generate a unique feedback token for verification
# This token MUST appear in the exported CSV to prove the agent included feedback
TOKEN="VERIFY_$(date +%s)_$RANDOM"
echo "$TOKEN" > /tmp/feedback_token.txt
echo "Generated verification token: $TOKEN"

# 5. Insert/Update Grade with Feedback containing the token
# Check if grade exists
GRADE_EXISTS=$(moodle_query "SELECT id FROM mdl_grade_grades WHERE itemid=$ITEM_ID AND userid=$USER_ID" | tr -d '[:space:]')

if [ -n "$GRADE_EXISTS" ]; then
    echo "Updating existing grade for jsmith..."
    moodle_query "UPDATE mdl_grade_grades SET finalgrade=85.00, feedback='Excellent work. $TOKEN', feedbackformat=1, timemodified=$(date +%s) WHERE id=$GRADE_EXISTS"
else
    echo "Inserting new grade for jsmith..."
    moodle_query "INSERT INTO mdl_grade_grades (itemid, userid, rawgrade, finalgrade, feedback, feedbackformat, timecreated, timemodified) VALUES ($ITEM_ID, $USER_ID, 85.00, 85.00, 'Excellent work. $TOKEN', 1, $(date +%s), $(date +%s))"
fi

# 6. Ensure Firefox is running
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 7. Focus and maximize
wait_for_window "firefox\|mozilla\|Moodle" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 8. Record Start Time
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Token injected into database: $TOKEN"