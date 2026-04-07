#!/bin/bash
echo "=== Setting up setup_grading_rubric task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Wait for Moodle to be fully ready
wait_for_moodle 120

# 2. Create the course and assignment via PHP CLI
cat > /tmp/setup_rubric_course.php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot.'/course/lib.php');
require_once($CFG->dirroot.'/course/modlib.php');

global $DB;

// Create or get course
$course = $DB->get_record('course', array('shortname' => 'PSY101'));
if (!$course) {
    $coursedata = new stdClass();
    $coursedata->fullname = 'Introduction to Psychology';
    $coursedata->shortname = 'PSY101';
    $coursedata->category = 1;
    $coursedata->startdate = time();
    $coursedata->visible = 1;
    $course = create_course($coursedata);
    echo "Created course PSY101.\n";
} else {
    echo "Course PSY101 already exists.\n";
}

// Create or get assignment
$assign = $DB->get_record('assign', array('course' => $course->id, 'name' => 'Final Research Paper'));
if (!$assign) {
    $module = new stdClass();
    $module->course = $course->id;
    $module->modulename = 'assign';
    $module->name = 'Final Research Paper';
    $module->intro = 'Submit your final research paper here.';
    $module->introformat = FORMAT_HTML;
    $module->assignsubmission_onlinetext_enabled = 1;
    $module->assignsubmission_file_enabled = 1;
    $module->alwaysshowdescription = 1;
    $module->submissiondrafts = 0;
    $module->requiresubmissionstatement = 0;
    $module->sendnotifications = 0;
    $module->sendlatenotifications = 0;
    $module->duedate = time() + (7 * 24 * 60 * 60);
    $module->grade = 100;
    
    $cm = add_moduleinfo($module, $course);
    echo "Created assignment 'Final Research Paper'.\n";
} else {
    echo "Assignment already exists.\n";
}
PHPEOF

sudo -u www-data php /tmp/setup_rubric_course.php

# 3. Create the data file for the agent to transcribe
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/paper_rubric.txt << 'EOF'
DEPARTMENTAL GRADING RUBRIC - WRITTEN COMMUNICATION

Task: Final Research Paper
Course: Introduction to Psychology (PSY101)

Please configure the following grading rubric in the LMS:

Rubric Name: Research Paper Evaluation

CRITERIA 1: Thesis and Argument
- Missing or unclear thesis (0 points)
- Thesis is present but lacks arguable claim (10 points)
- Clear, arguable, and specific thesis (20 points)

CRITERIA 2: Evidence and Analysis
- Little to no evidence provided (0 points)
- Adequate evidence but superficial analysis (15 points)
- Robust evidence paired with deep, critical analysis (30 points)

CRITERIA 3: Organization and Mechanics
- Poor structure, frequent errors (0 points)
- Basic structure, some distracting errors (5 points)
- Logical flow, minimal to no errors (10 points)
EOF

chown -R ga:ga /home/ga/Documents
chmod 644 /home/ga/Documents/paper_rubric.txt

# 4. Launch Firefox and point to the Moodle login page
echo "Launching Firefox..."
restart_firefox "http://localhost/login/index.php"

# Allow time for browser to render
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga
echo "Initial state screenshot saved."

echo "=== Task setup complete ==="