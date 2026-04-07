#!/bin/bash
set -e

echo "=== Setting up Marking Guide Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Course and Assignment using Moodle PHP API
# This ensures all contexts and module associations are created correctly
echo "Creating initial data via PHP..."

sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot . '/course/lib.php');
require_once(\$CFG->dirroot . '/mod/assign/lib.php');

// 1. Create Course HIST201 if it doesn't exist
\$course = \$DB->get_record('course', ['shortname' => 'HIST201']);
if (!\$course) {
    \$coursedata = new stdClass();
    \$coursedata->fullname = 'World History';
    \$coursedata->shortname = 'HIST201';
    \$coursedata->category = 1; // Default category
    \$course = create_course(\$coursedata);
    echo \"Created course: HIST201\n\";
} else {
    echo \"Course HIST201 already exists\n\";
}

// 2. Create Assignment if it doesn't exist
\$assign = \$DB->get_record('assign', ['course' => \$course->id, 'name' => 'Industrial Revolution Research Paper']);
if (!\$assign) {
    \$module = \$DB->get_record('modules', ['name' => 'assign']);
    
    \$data = new stdClass();
    \$data->course = \$course->id;
    \$data->name = 'Industrial Revolution Research Paper';
    \$data->intro = 'Write a research paper on the social and economic impacts of the Industrial Revolution.';
    \$data->introformat = FORMAT_HTML;
    \$data->gradingmethod = 'simple'; // Start with simple grading
    \$data->submissiondrafts = 0;
    \$data->requiresubmissionstatement = 0;
    \$data->sendnotifications = 0;
    \$data->sendlatenotifications = 0;
    \$data->duedate = time() + 7 * 24 * 60 * 60;
    \$data->cutoffdate = 0;
    \$data->allowsubmissionsfromdate = time();
    \$data->grade = 100;
    \$data->modulename = 'assign';
    \$data->module = \$module->id;
    \$data->section = 1;
    \$data->visible = 1;

    // Use add_moduleinfo to create the course module and instance
    \$info = add_moduleinfo(\$data, \$course);
    echo \"Created assignment: Industrial Revolution Research Paper\n\";
} else {
    // Reset to simple grading if it exists
    \$DB->set_field('assign', 'gradingmethod', 'simple', ['id' => \$assign->id]);
    
    // Clean up any existing advanced grading definitions for this assignment to ensure clean state
    \$cm = get_coursemodule_from_instance('assign', \$assign->id, \$course->id);
    \$context = context_module::instance(\$cm->id);
    
    // Delete from grading_areas and definitions
    // This is a rough cleanup, proper API usage would be better but this suffices for setup
    \$areas = \$DB->get_records('grading_areas', ['contextid' => \$context->id]);
    foreach (\$areas as \$area) {
        \$DB->delete_records('grading_definitions', ['areaid' => \$area->id]);
        \$DB->delete_records('grading_areas', ['id' => \$area->id]);
    }
    echo \"Reset assignment to simple grading\n\";
}
"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
MOODLE_URL="http://localhost/moodle/course/search.php?search=HIST201"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|Moodle" 30

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="