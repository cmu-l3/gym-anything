#!/bin/bash
set -e
echo "=== Setting up Configure Assignment Rubric Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt

# Wait for Moodle web service to be fully responsive
wait_for_moodle 120

# Create the target course and assignment via Moodle PHP API
echo "Creating course and assignment..."
cat > /tmp/setup_rubric_course.php << 'PHP_EOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot.'/course/lib.php');
require_once($CFG->dirroot.'/mod/assign/locallib.php');

global $DB, $USER;
$admin = $DB->get_record('user', ['username' => 'admin']);
cron_setup_user($admin);

// Create English 101 course
$course = new stdClass();
$course->fullname = 'English 101';
$course->shortname = 'ENG101_' . time();
$course->category = 1;
$course->visible = 1;
$course = create_course($course);

// Create Final Analytical Essay assignment
$assign = new stdClass();
$assign->course = $course->id;
$assign->name = 'Final Analytical Essay';
$assign->intro = 'Please submit your final analytical essay here for grading via the official rubric.';
$assign->introformat = FORMAT_HTML;
$assign->assignsubmission_file_enabled = 1;
$assign->assignsubmission_onlinetext_enabled = 1;
$assign->submissiondrafts = 0;
$assign->requiresubmissionstatement = 0;
$assign->sendnotifications = 0;
$assign->sendlatenotifications = 0;
$assign->duedate = time() + (7 * 24 * 60 * 60);
$assign->grade = 100;
$assign->visible = 1;

$module = $DB->get_record('modules', ['name' => 'assign']);
$assign->module = $module->id;
$assign->modulename = 'assign';
$assign->section = 1;

$cm = add_course_module($assign);
$assign->coursemodule = $cm->id;
$assign->section = course_add_cm_to_section($course, $cm->id, 1);
$DB->set_field('course_modules', 'section', $assign->section, ['id' => $cm->id]);
$assign->instance = $DB->insert_record('assign', $assign);
$DB->set_field('course_modules', 'instance', $assign->instance, ['id' => $cm->id]);

rebuild_course_cache($course->id);
echo "Course and Assignment created successfully.\n";
PHP_EOF

sudo -u www-data php /tmp/setup_rubric_course.php

# Create the source markdown file on the desktop
echo "Generating rubric reference document..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/rubric_definition.md << 'MD_EOF'
# Analytical Essay Rubric

**Criterion 1: Content Development**
* 0 points: Uses appropriate and relevant content to develop simple ideas in some parts of the work.
* 1 point: Uses appropriate, relevant, and compelling content to explore ideas within the context of the discipline.
* 2 points: Uses appropriate, relevant, and compelling content to illustrate mastery of the subject.

**Criterion 2: Sources and Evidence**
* 0 points: Demonstrates an attempt to use sources to support ideas.
* 1 point: Demonstrates consistent use of credible, relevant sources to support ideas.
* 2 points: Demonstrates skillful use of high-quality, credible, relevant sources to develop ideas.

**Criterion 3: Syntax and Mechanics**
* 0 points: Uses language that sometimes impedes meaning because of errors in usage.
* 1 point: Uses straightforward language that generally conveys meaning to readers.
* 2 points: Uses graceful language that skillfully communicates meaning to readers with clarity.
MD_EOF
chown ga:ga /home/ga/Desktop/rubric_definition.md
chmod 644 /home/ga/Desktop/rubric_definition.md

# Launch Firefox
echo "Starting Firefox..."
restart_firefox "http://localhost/my/"

# Allow UI to stabilize
sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="