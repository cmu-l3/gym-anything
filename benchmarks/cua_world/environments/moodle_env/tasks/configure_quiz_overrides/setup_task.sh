#!/bin/bash
# Setup script for Configure Quiz Overrides task

echo "=== Setting up Configure Quiz Overrides Task ==="

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
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
fi

# =============================================================================
# 1. Ensure Data Exists (PHP Script)
# =============================================================================
# We need:
# - Course BIO101
# - Quiz "Midterm Exam: Cell Biology"
# - Group "Extended Time Group" with members
# - Student epatel enrolled

echo "Running PHP setup script..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');
require_once(\$CFG->dirroot . '/mod/quiz/lib.php');
require_once(\$CFG->dirroot . '/group/lib.php');
require_once(\$CFG->dirroot . '/user/lib.php');

// 1. Get Course BIO101
\$course = \$DB->get_record('course', ['shortname' => 'BIO101']);
if (!\$course) {
    echo 'Error: BIO101 not found. Creating...';
    // Create if missing (fallback)
    \$category = \$DB->get_record('course_categories', ['name' => 'Science']);
    \$cdata = new stdClass();
    \$cdata->fullname = 'Introduction to Biology';
    \$cdata->shortname = 'BIO101';
    \$cdata->category = \$category ? \$category->id : 1;
    \$course = create_course(\$cdata);
}
echo 'Course ID: ' . \$course->id . \"\n\";

// 2. Ensure Student epatel exists and is enrolled
\$user = \$DB->get_record('user', ['username' => 'epatel', 'deleted' => 0]);
if (\$user) {
    if (!is_enrolled(context_course::instance(\$course->id), \$user->id)) {
        \$enrol = enrol_get_plugin('manual');
        \$instance = \$DB->get_record('enrol', ['courseid' => \$course->id, 'enrol' => 'manual']);
        \$enrol->enrol_user(\$instance, \$user->id, 5); // 5 = student role
        echo 'Enrolled epatel' . \"\n\";
    }
} else {
    echo 'Error: User epatel not found' . \"\n\";
}

// 3. Create/Reset Quiz
\$quiz = \$DB->get_record('quiz', ['course' => \$course->id, 'name' => 'Midterm Exam: Cell Biology']);
if (!\$quiz) {
    echo 'Creating Quiz...' . \"\n\";
    \$module = \$DB->get_record('modules', ['name' => 'quiz']);
    
    \$quiz = new stdClass();
    \$quiz->course = \$course->id;
    \$quiz->name = 'Midterm Exam: Cell Biology';
    \$quiz->intro = 'Midterm exam covering cell structure.';
    \$quiz->introformat = 1;
    \$quiz->timeopen = 0;
    \$quiz->timeclose = 0;
    \$quiz->timelimit = 3600; // 60 minutes
    \$quiz->attempts = 1;
    \$quiz->grade = 10;
    \$quiz->preferredbehaviour = 'deferredfeedback';
    
    // Create course module and add instance
    \$cm = new stdClass();
    \$cm->course = \$course->id;
    \$cm->module = \$module->id;
    \$cm->section = 1;
    
    \$quiz->id = quiz_add_instance(\$quiz, \$cm);
    \$cm->instance = \$quiz->id;
    \$cm->id = add_course_module(\$cm);
    \$section = \$DB->get_record('course_sections', ['course' => \$course->id, 'section' => 1]);
    course_add_cm_to_section(\$course, \$cm->id, 1);
    
    // Rebuild course cache
    rebuild_course_cache(\$course->id);
} else {
    // Reset quiz settings to ensure clean state
    \$update = new stdClass();
    \$update->id = \$quiz->id;
    \$update->timelimit = 3600;
    \$update->attempts = 1;
    \$DB->update_record('quiz', \$update);
    echo 'Reset existing quiz' . \"\n\";
}
echo 'Quiz ID: ' . \$quiz->id . \"\n\";

// 4. Clear any existing overrides
\$DB->delete_records('quiz_overrides', ['quiz' => \$quiz->id]);
echo 'Cleared existing overrides' . \"\n\";

// 5. Create Group
\$groupname = 'Extended Time Group';
\$group = \$DB->get_record('groups', ['courseid' => \$course->id, 'name' => \$groupname]);
if (!\$group) {
    \$data = new stdClass();
    \$data->courseid = \$course->id;
    \$data->name = \$groupname;
    \$groupid = groups_create_group(\$data);
    \$group = \$DB->get_record('groups', ['id' => \$groupid]);
    echo 'Created Group: ' . \$groupname . \"\n\";
} else {
    echo 'Group exists: ' . \$groupname . \"\n\";
}

// 6. Add members to group (bbrown, cgarcia)
\$members = ['bbrown', 'cgarcia'];
foreach (\$members as \$m_username) {
    \$m_user = \$DB->get_record('user', ['username' => \$m_username, 'deleted' => 0]);
    if (\$m_user) {
        // Ensure enrolled first
        if (!is_enrolled(context_course::instance(\$course->id), \$m_user->id)) {
            \$enrol = enrol_get_plugin('manual');
            \$instance = \$DB->get_record('enrol', ['courseid' => \$course->id, 'enrol' => 'manual']);
            \$enrol->enrol_user(\$instance, \$m_user->id, 5);
        }
        groups_add_member(\$group->id, \$m_user->id);
    }
}

file_put_contents('/tmp/quiz_id.txt', \$quiz->id);
file_put_contents('/tmp/group_id.txt', \$group->id);
file_put_contents('/tmp/user_id.txt', \$user->id);
"

# =============================================================================
# 2. Record Initial State
# =============================================================================

QUIZ_ID=$(cat /tmp/quiz_id.txt 2>/dev/null || echo "0")
echo "Target Quiz ID: $QUIZ_ID"

# Record initial override count (should be 0)
INITIAL_OVERRIDE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_overrides WHERE quiz=$QUIZ_ID" | tr -d '[:space:]')
echo "$INITIAL_OVERRIDE_COUNT" > /tmp/initial_override_count
echo "Initial override count: $INITIAL_OVERRIDE_COUNT"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# =============================================================================
# 3. Launch Application
# =============================================================================

echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/moodle/course/view.php?name=BIO101"

if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="