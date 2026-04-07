#!/bin/bash
echo "=== Setting up grant_quiz_accommodations task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Moodle to be ready
wait_for_moodle 60

echo "Configuring Moodle environment (Course, Quiz, Enrollments)..."

# Run a self-contained PHP script to configure the exact starting state
cat > /tmp/setup_accommodations.php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot.'/course/lib.php');

// 1. Get or Create Category
$cat = $DB->get_record('course_categories', array(), '*', IGNORE_MULTIPLE);
if (!$cat) {
    $cat = new stdClass();
    $cat->name = 'Miscellaneous';
    $cat->id = $DB->insert_record('course_categories', $cat);
}

// 2. Create Course
$course = new stdClass();
$course->fullname = 'NURS101: Fundamentals of Nursing';
$course->shortname = 'NURS101';
$course->category = $cat->id;
$course->visible = 1;
$course->startdate = time();
$course = create_course($course);

// 3. Create Course Module entry
$module = $DB->get_record('modules', ['name' => 'quiz']);
$cm = new stdClass();
$cm->course = $course->id;
$cm->module = $module->id;
$cm->section = 1;
$cm->added = time();
$cm->visible = 1;
$cmid = $DB->insert_record('course_modules', $cm);

// 4. Create Quiz Instance
$quiz = new stdClass();
$quiz->course = $course->id;
$quiz->name = 'Midterm Examination';
$quiz->intro = 'Midterm Exam for NURS101';
$quiz->introformat = FORMAT_HTML;
$quiz->timelimit = 3600; // 60 minutes
$quiz->attempts = 1;
$quiz->coursemodule = $cmid;
$quiz->timeopen = 0;
$quiz->timeclose = 0;
$quiz->grademethod = 1;
$quiz->sumgrades = 100;
$quiz->grade = 100;
$quizid = $DB->insert_record('quiz', $quiz);

// 5. Update Course Module mapping
$cm->id = $cmid;
$cm->instance = $quizid;
$DB->update_record('course_modules', $cm);

// 6. Update Course Section
$section = $DB->get_record('course_sections', ['course' => $course->id, 'section' => 1]);
if ($section) {
    $section->sequence = $cmid;
    $DB->update_record('course_sections', $section);
} else {
    $section = new stdClass();
    $section->course = $course->id;
    $section->section = 1;
    $section->sequence = $cmid;
    $DB->insert_record('course_sections', $section);
}

// 7. Enroll Target Users
$enrol = enrol_get_plugin('manual');
$enrolinstance = $DB->get_record('enrol', ['courseid' => $course->id, 'enrol' => 'manual'], '*', IGNORE_MULTIPLE);
$studentrole = $DB->get_record('role', ['shortname' => 'student']);

foreach(['awilson', 'bbrown', 'jsmith', 'mjones'] as $uname) {
    $u = $DB->get_record('user', ['username' => $uname]);
    if ($u && $enrolinstance && $studentrole) {
        $enrol->enrol_user($enrolinstance, $u->id, $studentrole->id);
    }
}

// 8. Rebuild Cache
rebuild_course_cache($course->id);
echo "SUCCESS";
PHPEOF

sudo -u www-data php /tmp/setup_accommodations.php

# Start Firefox at Moodle home
echo "Starting Firefox..."
restart_firefox "http://localhost/login/index.php"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="