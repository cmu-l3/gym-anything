#!/bin/bash
# Setup script for Setup Competency Framework task

echo "=== Setting up Competency Framework Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
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
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
fi

echo "--- Creating PSY301 course and assignments via PHP CLI ---"

sudo -u www-data php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot . '/course/lib.php');

// Set up admin user context for module creation
global $USER;
$USER = get_admin();

// Enable competencies site-wide
set_config('enablecompetencies', 1);
echo "Competencies enabled\n";

// Get Humanities category
$hum_cat = $DB->get_record('course_categories', ['idnumber' => 'HUM']);
$hum_id = $hum_cat ? $hum_cat->id : 1;
echo "Humanities category id=$hum_id\n";

// Create PSY301 if not exists
if (!$DB->record_exists('course', ['shortname' => 'PSY301'])) {
    $course = new stdClass();
    $course->fullname = 'Educational Psychology';
    $course->shortname = 'PSY301';
    $course->category = $hum_id;
    $course->format = 'topics';
    $course->numsections = 8;
    $course->visible = 1;
    $course->startdate = mktime(0, 0, 0, 9, 1, 2025);
    $course->summary = 'Explores the psychological foundations of education, learning theories, developmental stages, and assessment methods used in educational settings.';
    $course->summaryformat = FORMAT_HTML;
    $newcourse = create_course($course);
    echo "Created PSY301 id=" . $newcourse->id . "\n";
} else {
    echo "PSY301 already exists\n";
}

$course = $DB->get_record('course', ['shortname' => 'PSY301'], '*', MUST_EXIST);
$courseid = $course->id;
echo "PSY301 course id=$courseid\n";

// Create 3 assignments
require_once($CFG->dirroot . '/mod/assign/lib.php');
$assignments = [
    [
        'name' => 'Learning Theories Essay',
        'intro' => 'Write a 2000-word essay comparing and contrasting behaviorism, cognitivism, and constructivism. Analyze how each theory applies to modern classroom instruction.',
    ],
    [
        'name' => 'Child Development Case Study',
        'intro' => 'Select a child aged 6-12 and write a developmental case study applying Piaget\'s cognitive development theory and Erikson\'s psychosocial stages.',
    ],
    [
        'name' => 'Assessment Design Project',
        'intro' => 'Design a comprehensive assessment plan for a unit of your choice, including formative assessments, summative assessments, rubrics, and alignment to learning objectives.',
    ],
];

require_once($CFG->dirroot . '/mod/assign/lib.php');
$module = $DB->get_record('modules', ['name' => 'assign'], '*', MUST_EXIST);
foreach ($assignments as $idx => $ainfo) {
    // Check if already exists
    if ($DB->record_exists('assign', ['course' => $courseid, 'name' => $ainfo['name']])) {
        echo "Assignment already exists: " . $ainfo['name'] . "\n";
        continue;
    }
    $assign = new stdClass();
    $assign->course = $courseid;
    $assign->name = $ainfo['name'];
    $assign->intro = $ainfo['intro'];
    $assign->introformat = FORMAT_HTML;
    $assign->alwaysshowdescription = 1;
    $assign->submissiondrafts = 0;
    $assign->sendnotifications = 0;
    $assign->sendlatenotifications = 0;
    $assign->sendstudentnotifications = 1;
    $assign->duedate = 0;
    $assign->allowsubmissionsfromdate = 0;
    $assign->cutoffdate = 0;
    $assign->gradingduedate = 0;
    $assign->grade = 100;
    $assign->timemodified = time();
    $assign->completionsubmit = 0;
    $assign->requiresubmissionstatement = 0;
    $assign->teamsubmission = 0;
    $assign->requireallteammemberssubmit = 0;
    $assign->teamsubmissiongroupingid = 0;
    $assign->blindmarking = 0;
    $assign->hidegrader = 0;
    $assign->revealidentities = 0;
    $assign->attemptreopenmethod = 'none';
    $assign->maxattempts = -1;
    $assign->markingworkflow = 0;
    $assign->markingallocation = 0;
    $assign->id = 0;
    try {
        $assign->id = assign_add_instance($assign, null);
        echo "Assignment '" . $ainfo['name'] . "' created via API\n";
    } catch (Throwable $e) {
        echo "Assignment '" . $ainfo['name'] . "' API failed: " . $e->getMessage() . "\n";
        try {
            $assign->id = $DB->insert_record('assign', $assign);
            echo "Assignment '" . $ainfo['name'] . "' via direct insert\n";
        } catch (Throwable $e2) {
            echo "Assignment '" . $ainfo['name'] . "' direct insert also failed: " . $e2->getMessage() . "\n";
        }
    }
    if (!$assign->id) {
        echo "ERROR: Failed to create assignment: " . $ainfo['name'] . "\n";
        continue;
    }

    $cm = new stdClass();
    $cm->course = $courseid;
    $cm->module = $module->id;
    $cm->instance = $assign->id;
    $cm->section = $idx + 1;
    $cm->visible = 1;
    $cm->completion = 0;
    $cmid = add_course_module($cm);
    course_add_cm_to_section($course, $cmid, $idx + 1);
    context_module::instance($cmid);
    echo "Created assignment: " . $ainfo['name'] . " (cmid=$cmid)\n";
}

echo "SETUP_COMPLETE courseid=$courseid\n";
PHPEOF

PHP_EXIT=$?
if [ $PHP_EXIT -ne 0 ]; then
    echo "WARNING: PHP setup exited with code $PHP_EXIT"
fi

# Save baselines for the verifier
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='PSY301'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: PSY301 course not found after PHP setup!"
    exit 1
fi
echo "PSY301 Course ID: $COURSE_ID"

INITIAL_FRAMEWORK_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency_framework" 2>/dev/null | tr -d '[:space:]')
echo "$COURSE_ID" > /tmp/psy301_course_id
echo "${INITIAL_FRAMEWORK_COUNT:-0}" > /tmp/psy301_initial_framework_count
echo "Initial framework count: ${INITIAL_FRAMEWORK_COUNT:-0}"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
