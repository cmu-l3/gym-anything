#!/bin/bash
# Setup script for Configure Self Enrollment task

echo "=== Setting up Configure Self Enrollment Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
fi

# Ensure CHEM101 course exists
echo "Checking/Creating CHEM101 course..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');

if (!\$course = \$DB->get_record('course', array('shortname' => 'CHEM101'))) {
    \$category = \$DB->get_record('course_categories', array('name' => 'Science'));
    \$catid = \$category ? \$category->id : 1;
    
    \$data = new stdClass();
    \$data->fullname = 'General Chemistry';
    \$data->shortname = 'CHEM101';
    \$data->category = \$catid;
    \$data->visible = 1;
    \$data->startdate = time();
    \$data->summary = 'Introduction to chemical principles and laboratory safety.';
    
    try {
        \$course = create_course(\$data);
        echo 'Created CHEM101 course with ID: ' . \$course->id . \"\n\";
    } catch (Exception \$e) {
        echo 'Error creating course: ' . \$e->getMessage() . \"\n\";
        exit(1);
    }
} else {
    echo 'CHEM101 course already exists (ID: ' . \$course->id . \")\n\";
}
"

# Get Course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')
echo "CHEM101 Course ID: $COURSE_ID"
echo "$COURSE_ID" > /tmp/chem101_id.txt

# Record initial state of self-enrollment (for anti-gaming)
# We look for any existing self-enrollment instances
INITIAL_SELF_ENROL=$(moodle_query "SELECT id, status, password, customint3, enrolperiod, name FROM mdl_enrol WHERE courseid=$COURSE_ID AND enrol='self'" 2>/dev/null || echo "")
echo "$INITIAL_SELF_ENROL" > /tmp/initial_self_enrol_state.txt
echo "Initial self-enrollment state recorded"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running
MOODLE_URL="http://localhost/"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for and focus Firefox
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|moodle"; then
        break
    fi
    sleep 1
done

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="