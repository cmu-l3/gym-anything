#!/bin/bash
set -e
echo "=== Setting up Configure Weighted Gradebook Task ==="

source /workspace/scripts/task_utils.sh

# Wait for Moodle to be ready
wait_for_moodle 120

# Record task start time
TASK_START_TIME=$(date +%s)
echo "$TASK_START_TIME" > /tmp/task_start_time.txt

# Create the specific Thermodynamics course via Moodle PHP API
echo "Creating Thermodynamics (ENG201) course..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot.'/course/lib.php');

// Check if course already exists to avoid fatal errors on retry
if (!\$DB->record_exists('course', array('shortname' => 'ENG201'))) {
    \$category = \$DB->get_record('course_categories', array(), '*', IGNORE_MULTIPLE);
    
    \$course = new stdClass();
    \$course->fullname = 'Thermodynamics';
    \$course->shortname = 'ENG201';
    \$course->category = \$category->id;
    \$course->visible = 1;
    \$course->startdate = time();
    \$course->format = 'topics';
    
    create_course(\$course);
    echo \"Course ENG201 created successfully.\n\";
} else {
    echo \"Course ENG201 already exists.\n\";
}
" || echo "Note: Course creation script encountered a warning, continuing..."

# Start Firefox and navigate to the login page
echo "Starting Firefox..."
restart_firefox "http://localhost/login/index.php"

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="