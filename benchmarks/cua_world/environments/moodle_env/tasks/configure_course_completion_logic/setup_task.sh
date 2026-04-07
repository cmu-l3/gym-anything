#!/bin/bash
# Setup script for Configure Course Completion Logic task

echo "=== Setting up Configure Course Completion Logic Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definition for moodle_query if not present (safety)
if ! type moodle_query &>/dev/null; then
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
    wait_for_window() {
        local window_pattern="$1"; local timeout=${2:-30}; local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then return 0; fi
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
fi

# ==============================================================================
# 1. Create Course and Activities via PHP CLI (Reliable Moodle State)
# ==============================================================================

echo "Creating course SAFE101 and activities..."

# Create a PHP script to set up the course state
cat > /tmp/setup_course.php << 'PHP'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/lib/gradelib.php');

// 1. Check if course exists, delete if so to ensure clean state
$existing = $DB->get_record('course', array('shortname' => 'SAFE101'));
if ($existing) {
    delete_course($existing, false);
}

// 2. Create Course
$course = new stdClass();
$course->fullname = 'Workplace Safety';
$course->shortname = 'SAFE101';
$course->category = 1; // Default category
$course->enablecompletion = 1; // Enable completion tracking at course level
$course->startdate = time();
$course->visible = 1;
$course = create_course($course);
echo "Course created: " . $course->id . "\n";

// 3. Create Page Resource (Employee Handbook)
// We use the generator for simplicity in CLI
$generator = \testing_util::get_data_generator();
$page = $generator->create_module('page', array(
    'course' => $course->id,
    'name' => 'Employee Handbook',
    'intro' => 'Please read this handbook carefully.',
    'content' => 'Safety rules and regulations...',
    'section' => 1,
    'completion' => 1 // Start with Manual completion (agent must change to Auto)
));
echo "Page created: " . $page->cmid . "\n";

// 4. Create Quiz Activity (Safety Certification Exam)
$quiz = $generator->create_module('quiz', array(
    'course' => $course->id,
    'name' => 'Safety Certification Exam',
    'intro' => 'Final certification exam.',
    'section' => 2,
    'grade' => 100,
    'completion' => 1 // Start with Manual completion
));
echo "Quiz created: " . $quiz->cmid . "\n";

// Ensure Grade item exists but has NO pass grade set
$gradeitem = \grade_item::fetch(array('itemtype'=>'mod', 'itemmodule'=>'quiz', 'iteminstance'=>$quiz->id, 'courseid'=>$course->id));
if ($gradeitem) {
    $gradeitem->gradepass = 0; // Reset to 0
    $gradeitem->update();
}
PHP

# Execute the PHP script
sudo -u www-data php /tmp/setup_course.php > /tmp/setup_course.log 2>&1
cat /tmp/setup_course.log

# Verify Creation
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='SAFE101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: Failed to create course SAFE101"
    exit 1
fi
echo "Course SAFE101 ID: $COURSE_ID"

# ==============================================================================
# 2. Browser Setup
# ==============================================================================

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running
MOODLE_URL="http://localhost/moodle/course/view.php?id=$COURSE_ID"

if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
else
    # Navigate to the specific course
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' &" 2>/dev/null
    sleep 3
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="