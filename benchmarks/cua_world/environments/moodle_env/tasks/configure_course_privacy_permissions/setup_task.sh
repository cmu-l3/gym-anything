#!/bin/bash
# Setup script for Configure Course Privacy Permissions task

echo "=== Setting up Privacy Permissions Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Get Course ID for HIST201
echo "Locating course HIST201..."
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='HIST201'" | tr -d '[:space:]')

if [ -z "$COURSE_ID" ]; then
    echo "ERROR: Course HIST201 not found. Creating it..."
    # Fallback: Create the course if it doesn't exist (though env usually has it)
    /usr/bin/php /var/www/html/moodle/admin/cli/create_course.php \
        --shortname="HIST201" \
        --fullname="World History" \
        --category="Humanities" 2>/dev/null
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='HIST201'" | tr -d '[:space:]')
fi
echo "Course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/target_course_id

# 2. Get Context ID for this course
# contextlevel 50 = COURSE
CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | tr -d '[:space:]')
echo "Course Context ID: $CONTEXT_ID"
echo "$CONTEXT_ID" > /tmp/target_context_id

# 3. Get Role ID for 'student'
ROLE_ID=$(moodle_query "SELECT id FROM mdl_role WHERE shortname='student'" | tr -d '[:space:]')
echo "Student Role ID: $ROLE_ID"
echo "$ROLE_ID" > /tmp/target_role_id

# 4. CLEANUP: Ensure no existing override exists for this capability in this context
if [ -n "$CONTEXT_ID" ] && [ -n "$ROLE_ID" ]; then
    echo "Clearing any existing overrides for moodle/course:viewparticipants in this course..."
    moodle_query "DELETE FROM mdl_role_capabilities WHERE contextid=$CONTEXT_ID AND roleid=$ROLE_ID AND capability='moodle/course:viewparticipants'"
fi

# 5. Record initial global state (System context usually ID 1, contextlevel 10)
# We check if 'student' is prevented globally (unlikely, but good to record)
SYSTEM_CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=10 ORDER BY id ASC LIMIT 1" | tr -d '[:space:]')
GLOBAL_PERM=$(moodle_query "SELECT permission FROM mdl_role_capabilities WHERE contextid=$SYSTEM_CONTEXT_ID AND roleid=$ROLE_ID AND capability='moodle/course:viewparticipants'" | tr -d '[:space:]')
echo "${GLOBAL_PERM:-0}" > /tmp/initial_global_perm
echo "Initial global permission: ${GLOBAL_PERM:-0} (0=Inherit/NotSet)"

# 6. Launch Firefox
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/moodle/course/view.php?id=$COURSE_ID"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
else
    # Navigate existing instance
    su - ga -c "DISPLAY=:1 firefox -new-tab '$MOODLE_URL' &"
    sleep 3
fi

# 7. Focus Window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="