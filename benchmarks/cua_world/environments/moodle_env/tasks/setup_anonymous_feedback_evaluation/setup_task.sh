#!/bin/bash
echo "=== Setting up Anonymous Feedback task ==="

# Source Moodle utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Moodle web service to be fully ready
wait_for_moodle 60

# 1. Create the Clinical Nursing Ethics course (NURS-401) via Moodle PHP CLI
echo "Creating Clinical Nursing Ethics course..."
sudo -u www-data php -r "
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once(\$CFG->dirroot.'/course/lib.php');

// Create category if needed, or use default (ID 1)
\$category_id = 1;

if (!\$DB->record_exists('course', array('shortname' => 'NURS-401'))) {
    \$course = new stdClass();
    \$course->fullname = 'Clinical Nursing Ethics';
    \$course->shortname = 'NURS-401';
    \$course->category = \$category_id;
    \$course->visible = 1;
    \$course->startdate = time();
    \$course->format = 'topics';
    \$course->numsections = 4;
    
    create_course(\$course);
    echo \"Course NURS-401 created successfully.\n\";
} else {
    echo \"Course NURS-401 already exists.\n\";
}
"

# 2. Start Firefox and log in as admin
echo "Starting Firefox and logging in..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/login/index.php' > /tmp/firefox.log 2>&1 &"
    sleep 6
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Automate Login using xdotool
echo "Executing login sequence..."
DISPLAY=:1 xdotool type "admin"
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type "Admin1234!"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 5

# Navigate to the newly created course
echo "Navigating to course page..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/course/view.php?name=NURS-401' > /dev/null 2>&1 &"
sleep 4

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="