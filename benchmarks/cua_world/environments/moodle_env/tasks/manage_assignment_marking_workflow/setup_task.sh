#!/bin/bash
# Setup script for Manage Assignment Marking Workflow task

echo "=== Setting up Manage Assignment Marking Workflow Task ==="

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
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
fi

# ==============================================================================
# PHP Script to Setup Data (Course, User, Assignment, Submission)
# ==============================================================================
cat > /tmp/setup_data.php << 'PHP'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot . '/course/lib.php');
require_once($CFG->dirroot . '/mod/assign/lib.php');
require_once($CFG->dirroot . '/user/lib.php');
require_once($CFG->dirroot . '/enrol/manual/lib.php');

// 1. Create Course HIST201
$course = $DB->get_record('course', array('shortname' => 'HIST201'));
if (!$course) {
    $category = $DB->get_record('course_categories', array('name' => 'Humanities'));
    if (!$category) {
        $category = new stdClass();
        $category->name = 'Humanities';
        $category = \core_course_category::create($category);
    }
    
    $c = new stdClass();
    $c->fullname = 'World History';
    $c->shortname = 'HIST201';
    $c->category = $category->id;
    $c->startdate = time();
    $course = create_course($c);
    echo "Created course HIST201\n";
} else {
    echo "Course HIST201 exists\n";
}

// 2. Create User bbrown
$user = $DB->get_record('user', array('username' => 'bbrown'));
if (!$user) {
    $u = new stdClass();
    $u->username = 'bbrown';
    $u->password = 'Student1234!';
    $u->firstname = 'Bob';
    $u->lastname = 'Brown';
    $u->email = 'bbrown@example.com';
    $u->confirmed = 1;
    $u->mnethostid = $CFG->mnet_localhost_id;
    $user_id = user_create_user($u);
    $user = $DB->get_record('user', array('id' => $user_id));
    echo "Created user bbrown\n";
} else {
    echo "User bbrown exists\n";
}

// 3. Enroll bbrown as Student
$enrol = enrol_get_plugin('manual');
$instance = $DB->get_record('enrol', array('courseid' => $course->id, 'enrol' => 'manual'));
if (!$instance) {
    $instance_id = $enrol->add_instance($course);
    $instance = $DB->get_record('enrol', array('id' => $instance_id));
}
$student_role = $DB->get_record('role', array('shortname' => 'student'));
if (!$DB->record_exists('user_enrolments', array('enrolid' => $instance->id, 'userid' => $user->id))) {
    $enrol->enrol_user($instance, $user->id, $student_role->id);
    echo "Enrolled bbrown in HIST201\n";
}

// 4. Create Assignment 'Final Research Paper'
$assign = $DB->get_record('assign', array('course' => $course->id, 'name' => 'Final Research Paper'));
if (!$assign) {
    $module = $DB->get_record('modules', array('name' => 'assign'));
    
    $a = new stdClass();
    $a->course = $course->id;
    $a->name = 'Final Research Paper';
    $a->intro = 'Submit your final research paper here.';
    $a->introformat = FORMAT_HTML;
    $a->alwaysshowdescription = 1;
    $a->submissiondrafts = 0;
    $a->sendnotifications = 0;
    $a->sendlatenotifications = 0;
    $a->duedate = time() + 7 * 24 * 60 * 60;
    $a->allowsubmissionsfromdate = time();
    $a->grade = 100;
    $a->markingworkflow = 0; // DISABLED INITIALLY - Task is to enable it
    $a->markingallocation = 0;
    
    // Create activity record
    $assign_id = $DB->insert_record('assign', $a);
    $a->id = $assign_id;
    
    // Create course module record
    $cm = new stdClass();
    $cm->course = $course->id;
    $cm->module = $module->id;
    $cm->instance = $assign_id;
    $cm->section = 1;
    $cm->visible = 1;
    $cm_id = add_course_module($cm);
    
    $section = $DB->get_record('course_sections', array('course' => $course->id, 'section' => 1));
    if (!$section) {
        $section = new stdClass();
        $section->course = $course->id;
        $section->section = 1;
        $DB->insert_record('course_sections', $section);
    }
    rebuild_course_cache($course->id);
    echo "Created assignment 'Final Research Paper'\n";
    $assign = $DB->get_record('assign', array('id' => $assign_id));
} else {
    // Reset workflow to 0 if it exists
    $assign->markingworkflow = 0;
    $DB->update_record('assign', $assign);
    echo "Reset markingworkflow to 0 for assignment\n";
}

// 5. Create a submission for bbrown
$submission = $DB->get_record('assign_submission', array('assignment' => $assign->id, 'userid' => $user->id));
if (!$submission) {
    $s = new stdClass();
    $s->assignment = $assign->id;
    $s->userid = $user->id;
    $s->timecreated = time();
    $s->timemodified = time();
    $s->status = 'submitted';
    $s->latest = 1;
    $s->attemptnumber = 0;
    $s->groupid = 0;
    $sid = $DB->insert_record('assign_submission', $s);
    
    // Add text submission content
    $plugin_s = new stdClass();
    $plugin_s->assignment = $assign->id;
    $plugin_s->submission = $sid;
    $plugin_s->onlinetext = "<p>Here is my final paper submission on the French Revolution.</p>";
    $plugin_s->onlineformat = 1;
    $DB->insert_record('assignsubmission_onlinetext', $plugin_s);
    
    echo "Created submission for bbrown\n";
}
PHP

# Execute PHP script
echo "Executing data setup..."
sudo -u www-data php /tmp/setup_data.php

# Cleanup PHP script
rm /tmp/setup_data.php

# ==============================================================================
# Browser Setup
# ==============================================================================

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
echo "Waiting for Moodle window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Moodle"; then
        break
    fi
    sleep 1
done

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