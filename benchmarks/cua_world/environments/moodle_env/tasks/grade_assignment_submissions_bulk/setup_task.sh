#!/bin/bash
# Setup script for Grade Assignment Submissions task

echo "=== Setting up Grade Assignment Submissions Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if not sourced correctly
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
    wait_for_window() {
        local window_pattern="$1"
        local timeout=${2:-30}
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then return 0; fi
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
fi

# 1. Create Course CHEM101
echo "Creating course CHEM101..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');

// Check if exists
if (!\$course = \$DB->get_record('course', ['shortname' => 'CHEM101'])) {
    \$data = new stdClass();
    \$data->fullname = 'Chemistry 101';
    \$data->shortname = 'CHEM101';
    \$data->category = 1; // Default category
    \$data->startdate = time();
    \$data->visible = 1;
    \$course = create_course(\$data);
    echo 'Created course CHEM101 (ID: ' . \$course->id . ')\n';
} else {
    echo 'Course CHEM101 already exists (ID: ' . \$course->id . ')\n';
}
file_put_contents('/tmp/chem101_id', \$course->id);
"

COURSE_ID=$(cat /tmp/chem101_id)

# 2. Create Assignment "Lab 3: Titration Analysis"
echo "Creating assignment..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');
require_once(\$CFG->dirroot . '/mod/assign/lib.php');

\$courseid = $COURSE_ID;

// Check if exists
\$assign = \$DB->get_record('assign', ['course' => \$courseid, 'name' => 'Lab 3: Titration Analysis']);
if (!\$assign) {
    \$module = \$DB->get_record('modules', ['name' => 'assign']);
    
    \$data = new stdClass();
    \$data->course = \$courseid;
    \$data->name = 'Lab 3: Titration Analysis';
    \$data->intro = 'Submit your titration analysis report here. Include error calculations.';
    \$data->introformat = FORMAT_HTML;
    \$data->alwaysshowdescription = 1;
    \$data->submissiondrafts = 0;
    \$data->sendnotifications = 0;
    \$data->sendlatenotifications = 0;
    \$data->duedate = time() + 7 * 24 * 3600;
    \$data->grade = 100;
    \$data->modulename = 'assign';
    \$data->module = \$module->id;
    \$data->section = 1;
    \$data->visible = 1;
    
    // Add module
    \$data->coursemodule = add_course_module(\$data);
    \$data->section = 1;
    \$data->id = \$data->coursemodule;
    
    // Add assignment instance
    \$data->instance = assign_add_instance(\$data, null);
    
    // Update course module
    \$DB->set_field('course_modules', 'instance', \$data->instance, ['id' => \$data->coursemodule]);
    
    // Rebuild course cache
    rebuild_course_cache(\$courseid);
    
    echo 'Created assignment Lab 3 (ID: ' . \$data->instance . ')\n';
} else {
    echo 'Assignment already exists\n';
}
"

# 3. Enroll Users
echo "Enrolling users..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/enrol/manual/locallib.php');

\$courseid = $COURSE_ID;
\$enrol = enrol_get_plugin('manual');
\$instance = \$DB->get_record('enrol', ['courseid' => \$courseid, 'enrol' => 'manual']);

\$role_student = \$DB->get_record('role', ['shortname' => 'student']);
\$role_teacher = \$DB->get_record('role', ['shortname' => 'editingteacher']);

\$students = ['jsmith', 'mjones', 'awilson'];
foreach (\$students as \$uname) {
    \$user = \$DB->get_record('user', ['username' => \$uname]);
    if (\$user) {
        if (!\$DB->record_exists('user_enrolments', ['enrolid' => \$instance->id, 'userid' => \$user->id])) {
            \$enrol->enrol_user(\$instance, \$user->id, \$role_student->id);
            echo \"Enrolled \$uname\n\";
        }
    }
}

\$teacher = \$DB->get_record('user', ['username' => 'teacher1']);
if (\$teacher) {
    if (!\$DB->record_exists('user_enrolments', ['enrolid' => \$instance->id, 'userid' => \$teacher->id])) {
        \$enrol->enrol_user(\$instance, \$teacher->id, \$role_teacher->id);
        echo \"Enrolled teacher1\n\";
    }
}
"

# Record start time for grading timestamps
date +%s > /tmp/task_start_time

# 4. Launch Firefox as Teacher
echo "Launching Firefox..."
MOODLE_URL="http://localhost/moodle/course/view.php?id=$COURSE_ID"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Teacher Login: teacher1 / Teacher1234!"