#!/bin/bash
# Setup script for Course Meta Link Enrollment task

echo "=== Setting up Course Meta Link Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ==============================================================================
# 1. PREPARE DATA (Courses and Initial Enrollments)
# ==============================================================================
echo "Generating required courses and users..."

# We use a PHP script to ensure Moodle internal API handles contexts/caches correctly
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');
require_once(\$CFG->dirroot . '/user/lib.php');
require_once(\$CFG->dirroot . '/enrol/manual/lib.php');

// 1. Create Parent Course (BIO101)
\$parent_course = \$DB->get_record('course', ['shortname' => 'BIO101']);
if (!\$parent_course) {
    \$data = new stdClass();
    \$data->fullname = 'Introduction to Biology';
    \$data->shortname = 'BIO101';
    \$data->category = 1;
    \$data->visible = 1;
    \$parent_course = create_course(\$data);
    echo \"Created parent course BIO101 (ID: \$parent_course->id)\n\";
} else {
    echo \"Parent course BIO101 already exists (ID: \$parent_course->id)\n\";
}

// 2. Create Child Course (BIO101-LAB)
\$child_course = \$DB->get_record('course', ['shortname' => 'BIO101-LAB']);
if (!\$child_course) {
    \$data = new stdClass();
    \$data->fullname = 'Introduction to Biology Lab';
    \$data->shortname = 'BIO101-LAB';
    \$data->category = 1;
    \$data->visible = 1;
    \$child_course = create_course(\$data);
    echo \"Created child course BIO101-LAB (ID: \$child_course->id)\n\";
} else {
    echo \"Child course BIO101-LAB already exists (ID: \$child_course->id)\n\";
    
    // Clean up any existing meta links in the child course to ensure clean state
    \$DB->delete_records('enrol', ['courseid' => \$child_course->id, 'enrol' => 'meta']);
    echo \"Cleaned up existing meta links in BIO101-LAB\n\";
}

// 3. Create Students and Enrol in Parent Course ONLY
\$manual_plugin = enrol_get_plugin('manual');
\$manual_instance = \$DB->get_record('enrol', ['courseid' => \$parent_course->id, 'enrol' => 'manual']);
if (!\$manual_instance) {
    \$manual_plugin->add_instance(\$parent_course);
    \$manual_instance = \$DB->get_record('enrol', ['courseid' => \$parent_course->id, 'enrol' => 'manual']);
}

\$students = ['bio_student1', 'bio_student2', 'bio_student3'];
\$roleid = \$DB->get_record('role', ['shortname' => 'student'])->id;

foreach (\$students as \$username) {
    \$user = \$DB->get_record('user', ['username' => \$username]);
    if (!\$user) {
        \$user = create_user_record(\$username, 'Student1234!');
    }
    
    // Enrol in Parent
    if (!\$DB->record_exists('user_enrolments', ['enrolid' => \$manual_instance->id, 'userid' => \$user->id])) {
        \$manual_plugin->enrol_user(\$manual_instance, \$user->id, \$roleid);
        echo \"Enrolled \$username in BIO101\n\";
    }
    
    // Ensure NOT in Child (remove if exists)
    // We check all enrol instances in child
    \$instances = \$DB->get_records('enrol', ['courseid' => \$child_course->id]);
    foreach (\$instances as \$instance) {
        if (\$DB->record_exists('user_enrolments', ['enrolid' => \$instance->id, 'userid' => \$user->id])) {
            \$plugin = enrol_get_plugin(\$instance->enrol);
            \$plugin->unenrol_user(\$instance, \$user->id);
            echo \"Removed \$username from BIO101-LAB\n\";
        }
    }
}

// Output IDs for shell script
file_put_contents('/tmp/bio_ids.txt', \$parent_course->id . ':' . \$child_course->id);
"

# Read IDs
IDs=$(cat /tmp/bio_ids.txt)
PARENT_ID=$(echo $IDs | cut -d: -f1)
CHILD_ID=$(echo $IDs | cut -d: -f2)

echo "Parent Course ID: $PARENT_ID"
echo "Child Course ID: $CHILD_ID"
echo "$PARENT_ID" > /tmp/parent_course_id
echo "$CHILD_ID" > /tmp/child_course_id

# Record initial enrollment count in Child course (should be 0 or low)
INITIAL_CHILD_COUNT=$(get_enrollment_count "$CHILD_ID" 2>/dev/null || echo "0")
echo "$INITIAL_CHILD_COUNT" > /tmp/initial_child_enrollment

# ==============================================================================
# 2. BROWSER SETUP
# ==============================================================================
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/moodle/course/view.php?id=$CHILD_ID"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # Navigate to the child course if already open
    su - ga -c "DISPLAY=:1 firefox -new-tab '$MOODLE_URL' &"
    sleep 3
fi

# Focus and maximize
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions: Configure 'Introduction to Biology Lab' (BIO101-LAB) to inherit enrollments from 'Introduction to Biology' (BIO101)."