#!/bin/bash
echo "=== Setting up Restore Course Backup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure Moodle web service is ready
wait_for_moodle 120

echo "Generating a realistic Moodle course backup file (.mbz)..."
cd /var/www/html/moodle

# We use Moodle's built-in CLI to generate a small realistic course
sudo -u www-data php admin/tool/generator/cli/maketestcourse.php --shortname=QABACKUP --size=S 2>/dev/null || true

# Get the internal ID of the generated course
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='QABACKUP' LIMIT 1")

mkdir -p /home/ga/Downloads
chown ga:ga /home/ga/Downloads

if [ -n "$COURSE_ID" ]; then
    echo "Generated base course with ID: $COURSE_ID. Creating backup..."
    
    # Run the automated backup tool on this course
    sudo -u www-data php admin/cli/backup.php --courseid=$COURSE_ID --destination=/home/ga/Downloads/ 2>/dev/null
    
    # Rename the resulting backup file
    mv /home/ga/Downloads/backup-moodle2-course-*.mbz /home/ga/Downloads/moodle-qa-course.mbz 2>/dev/null || true
    
    # Delete the base course so the agent actually has to restore the backup
    cat > /tmp/delete_course.php << 'EOF'
<?php
define('CLI_SCRIPT', true);
require(__DIR__.'/config.php');
require_once($CFG->dirroot.'/course/lib.php');
delete_course($argv[1], false);
EOF
    sudo -u www-data php /tmp/delete_course.php "$COURSE_ID" 2>/dev/null
    echo "Base course deleted. Backup file ready."
else
    echo "WARNING: Generator failed. Falling back to downloading a public Moodle QA backup..."
    # Fallback to a real fixture from the Moodle HQ repository if generation fails
    wget -qO /home/ga/Downloads/moodle-qa-course.mbz "https://raw.githubusercontent.com/moodle/moodle/master/backup/util/tests/fixtures/moodle2_course_backup.mbz"
fi

# Ensure proper permissions for the agent
chown ga:ga /home/ga/Downloads/moodle-qa-course.mbz
chmod 644 /home/ga/Downloads/moodle-qa-course.mbz

# Fetch the Humanities category ID for later verification
HUMANITIES_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Humanities' LIMIT 1")
echo "$HUMANITIES_ID" > /tmp/humanities_id.txt

# Launch Firefox and automate the login process to save the agent time
echo "Starting Firefox and logging in as admin..."
restart_firefox "http://localhost/login/index.php"
sleep 5

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
    # Automate login typing
    DISPLAY=:1 xdotool type "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.5
    DISPLAY=:1 xdotool type "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 5
    
    # Dismiss any welcome tour popup if it appears
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize again to be safe
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot of the starting state
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="