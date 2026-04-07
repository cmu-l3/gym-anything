#!/bin/bash
set -e
echo "=== Setting up Clinical Rotation Choice Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Moodle web service is ready
wait_for_moodle 60

# Run a PHP script to ensure the Nursing Practicum course exists and is clean
cat > /tmp/setup_course.php << 'PHP_EOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot.'/course/lib.php');

global $DB;

// Find or create course category (Healthcare/Nursing)
$cat = $DB->get_record('course_categories', array('name' => 'Healthcare'));
if (!$cat) {
    $cat = new stdClass();
    $cat->name = 'Healthcare';
    $cat->description = 'Healthcare and Nursing Courses';
    $cat = \core_course_category::create($cat);
}

// Find or create the Nursing Practicum 101 course
$course = $DB->get_record('course', array('shortname' => 'NURS101'));
if (!$course) {
    $record = new stdClass();
    $record->fullname = 'Nursing Practicum 101';
    $record->shortname = 'NURS101';
    $record->category = $cat->id;
    $record->visible = 1;
    $record->format = 'topics';
    $record->numsections = 4;
    $course = create_course($record);
    echo "Created course NURS101 with ID: " . $course->id . "\n";
} else {
    echo "Course NURS101 already exists with ID: " . $course->id . "\n";
    
    // Clean up any existing Choice activities in this course to provide a clean state
    $choices = $DB->get_records('choice', array('course' => $course->id));
    if ($choices) {
        foreach ($choices as $choice) {
            course_delete_module($choice->id);
            echo "Deleted old choice activity ID: " . $choice->id . "\n";
        }
    }
}
PHP_EOF

echo "Configuring Moodle database state..."
sudo -u www-data php /tmp/setup_course.php > /tmp/course_setup.log 2>&1
rm -f /tmp/setup_course.php

# Get the initial count of Choice activities globally
INITIAL_CHOICE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_choice" 2>/dev/null || echo "0")
echo "$INITIAL_CHOICE_COUNT" > /tmp/initial_choice_count.txt

# Start Firefox and navigate to the Moodle dashboard
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/login/index.php' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window and maximize it
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Firefox window detected: $WID"
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Allow UI to stabilize
sleep 2

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="