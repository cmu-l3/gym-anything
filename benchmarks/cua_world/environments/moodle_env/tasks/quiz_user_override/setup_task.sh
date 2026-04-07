#!/bin/bash
set -e
echo "=== Setting up Quiz User Override Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Moodle to be ready
wait_for_moodle 60

# Inject specific, realistic task data using Moodle's internal PHP API
# This avoids raw SQL which can break Moodle's cache and internal logic
cat > /tmp/setup_task_data.php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
global $DB, $CFG;

echo "Setting up task data...\n";

// 1. Ensure user Alice Wilson exists
$user = $DB->get_record('user', ['username' => 'awilson']);
if (!$user) {
    $user = new stdClass();
    $user->username = 'awilson';
    $user->password = hash_internal_user_password('Student1234!');
    $user->firstname = 'Alice';
    $user->lastname = 'Wilson';
    $user->email = 'awilson@example.com';
    $user->confirmed = 1;
    $user->mnethostid = $CFG->mnet_localhost_id;
    $user->id = $DB->insert_record('user', $user);
    echo "Created user Alice Wilson.\n";
}

// 2. Ensure course exists
$course = $DB->get_record('course', ['shortname' => 'ap101']);
if (!$course) {
    $course = new stdClass();
    $course->fullname = 'Anatomy & Physiology 101';
    $course->shortname = 'ap101';
    $course->category = 1; // Assuming default category 1 exists
    $course->format = 'topics';
    $course->visible = 1;
    $course->startdate = time();
    require_once($CFG->dirroot.'/course/lib.php');
    $course = create_course($course);
    echo "Created course Anatomy & Physiology 101.\n";
}

// 3. Enroll Alice Wilson as a student
$enrol = enrol_get_plugin('manual');
$instances = enrol_get_instances($course->id, true);
$manualinstance = null;
foreach ($instances as $instance) {
    if ($instance->enrol === 'manual') { 
        $manualinstance = $instance; 
        break; 
    }
}
$studentrole = $DB->get_record('role', ['shortname' => 'student']);
if ($manualinstance && $studentrole && !$DB->record_exists('user_enrolments', ['enrolid' => $manualinstance->id, 'userid' => $user->id])) {
    $enrol->enrol_user($manualinstance, $user->id, $studentrole->id);
    echo "Enrolled Alice Wilson in course.\n";
}

// 4. Create Quiz Activity
$quiz = $DB->get_record('quiz', ['name' => 'Midterm Examination', 'course' => $course->id]);
if (!$quiz) {
    require_once($CFG->dirroot.'/course/modlib.php');
    
    $quiz = new stdClass();
    $quiz->modulename = 'quiz';
    $quiz->name = 'Midterm Examination';
    $quiz->introeditor = ['text' => 'Midterm examination for AP101. Standard time limit applies.', 'format' => FORMAT_HTML];
    $quiz->timeopen = time() - (86400 * 5); // Opened 5 days ago
    $quiz->timeclose = time() - 86400; // Closed yesterday
    $quiz->timelimit = 3600; // 60 minutes
    $quiz->overduehandling = 'autosubmit';
    $quiz->course = $course->id;
    $quiz->section = 1;
    $quiz->visible = 1;
    
    // add_moduleinfo handles inserting into mdl_quiz and mdl_course_modules safely
    add_moduleinfo($quiz, $course);
    echo "Created Midterm Examination quiz.\n";
}

// 5. Clear any existing overrides to ensure a clean slate
if ($quiz) {
    $DB->delete_records('quiz_overrides', ['quiz' => $quiz->id]);
}

rebuild_course_cache($course->id);
echo "Setup complete.\n";
PHPEOF

echo "Executing Moodle data generation..."
sudo -u www-data php /tmp/setup_task_data.php

# Start Firefox, navigate to Moodle login
restart_firefox "http://localhost/login/index.php"

# Give UI time to stabilize
sleep 2

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png ga

# Check DB to confirm setup
INITIAL_OVERRIDES=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_overrides" 2>/dev/null || echo "0")
echo "Initial overrides in DB: $INITIAL_OVERRIDES" > /tmp/initial_count.txt

echo "=== Task setup complete ==="