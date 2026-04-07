#!/bin/bash
echo "=== Setting up Configure Activity Dependencies task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Moodle to be ready
wait_for_moodle 120

# 1. Create the Workplace Ergonomics course and activities via PHP CLI script
# This guarantees a clean, exact starting state without relying on flaky web automation
cat > /tmp/setup_ergo_course.php << 'PHP_EOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot.'/course/lib.php');

try {
    // Ensure category exists
    $category = $DB->get_record_sql("SELECT * FROM {course_categories} ORDER BY id ASC", array(), IGNORE_MULTIPLE);
    if (!$category) {
        $cat = new stdClass();
        $cat->name = 'Training';
        $cat->id = $DB->insert_record('course_categories', $cat);
        $category = $cat;
    }

    // Check if course already exists, delete if it does to ensure clean state
    if ($existing = $DB->get_record('course', array('shortname' => 'ERGO101'))) {
        delete_course($existing, false);
    }

    // Create Course
    $course = new stdClass();
    $course->fullname = 'Workplace Ergonomics';
    $course->shortname = 'ERGO101';
    $course->category = $category->id;
    $course->summary = 'Required training for all corporate employees.';
    $course->summaryformat = FORMAT_HTML;
    $course->format = 'topics';
    $course->numsections = 1;
    $course->enablecompletion = 1; // CRITICAL: ensure completion tracking is enabled at course level
    $course->visible = 1;
    $course->startdate = time();
    $course = create_course($course);

    // Create Page Module (Ergonomics Guide)
    $page = new stdClass();
    $page->course = $course->id;
    $page->name = 'Ergonomics Guide';
    $page->content = '<p>Proper desk posture is essential.</p>';
    $page->timemodified = time();
    $page->id = $DB->insert_record('page', $page);

    $cm_page = new stdClass();
    $cm_page->course = $course->id;
    $cm_page->module = $DB->get_field('modules', 'id', array('name' => 'page'));
    $cm_page->instance = $page->id;
    $cm_page->section = 1;
    $cm_page->added = time();
    $cm_page->completion = 0; // Starts with no completion tracking
    $cm_page->visible = 1;
    $cm_page->id = $DB->insert_record('course_modules', $cm_page);

    // Create Choice Module (Policy Acknowledgment)
    $choice = new stdClass();
    $choice->course = $course->id;
    $choice->name = 'Policy Acknowledgment';
    $choice->text = 'Do you acknowledge that you have read and understood the ergonomics guide?';
    $choice->timemodified = time();
    $choice->id = $DB->insert_record('choice', $choice);

    $cm_choice = new stdClass();
    $cm_choice->course = $course->id;
    $cm_choice->module = $DB->get_field('modules', 'id', array('name' => 'choice'));
    $cm_choice->instance = $choice->id;
    $cm_choice->section = 1;
    $cm_choice->added = time();
    $cm_choice->completion = 0;
    $cm_choice->visible = 1;
    $cm_choice->id = $DB->insert_record('course_modules', $cm_choice);

    // Place into section 1
    $cw = new stdClass();
    $cw->course = $course->id;
    $cw->section = 1;
    $cw->sequence = $cm_page->id . ',' . $cm_choice->id;
    $cw->id = $DB->insert_record('course_sections', $cw);

    $cm_page->section = $cw->id;
    $cm_choice->section = $cw->id;
    $DB->update_record('course_modules', $cm_page);
    $DB->update_record('course_modules', $cm_choice);

    rebuild_course_cache($course->id);
    echo $course->id;

} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}
PHP_EOF

echo "Generating course and activities..."
COURSE_ID=$(sudo -u www-data php /tmp/setup_ergo_course.php)
echo "Course created with ID: $COURSE_ID"

# 2. Launch Firefox and auto-navigate
COURSE_URL="http://localhost/course/view.php?id=$COURSE_ID"
restart_firefox "$COURSE_URL"

# 3. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="