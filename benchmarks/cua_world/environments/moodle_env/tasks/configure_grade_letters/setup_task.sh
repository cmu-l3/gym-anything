#!/bin/bash
# Setup script for Configure Grade Letters task

echo "=== Setting up Configure Grade Letters Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure the NUR301 course exists
# We use PHP to ensure contexts are created correctly
echo "Ensuring NUR301 course exists..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');

\$shortname = 'NUR301';
\$fullname = 'Nursing Fundamentals';
\$categoryid = 1; // Default category

if (!\$course = \$DB->get_record('course', array('shortname' => \$shortname))) {
    \$data = new stdClass();
    \$data->fullname = \$fullname;
    \$data->shortname = \$shortname;
    \$data->category = \$categoryid;
    \$data->visible = 1;
    \$data->startdate = time();
    
    \$course = create_course(\$data);
    echo 'Created course: ' . \$course->id . PHP_EOL;
} else {
    echo 'Course exists: ' . \$course->id . PHP_EOL;
    
    // Reset grade letters if they exist to ensure clean state
    \$context = context_course::instance(\$course->id);
    \$DB->delete_records('grade_letters', array('contextid' => \$context->id));
    echo 'Reset grade letters for course context' . PHP_EOL;
}
"

# 2. Get Course ID and Context ID for verification baseline
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='NUR301'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: Failed to create/find NUR301 course"
    exit 1
fi

CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | tr -d '[:space:]')
echo "Course ID: $COURSE_ID, Context ID: $CONTEXT_ID"

# 3. Record initial state (should be 0 after reset)
INITIAL_LETTERS_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_grade_letters WHERE contextid=$CONTEXT_ID" | tr -d '[:space:]')
echo "$INITIAL_LETTERS_COUNT" > /tmp/initial_letters_count
echo "$CONTEXT_ID" > /tmp/target_context_id
echo "Initial grade letters count: $INITIAL_LETTERS_COUNT"

# 4. Record task start timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox
echo "Starting Firefox..."
MOODLE_URL="http://localhost/moodle/login/index.php"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 6. Wait for window and maximize
if wait_for_window "firefox\|mozilla\|Moodle" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    echo "WARNING: Firefox window not detected"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="