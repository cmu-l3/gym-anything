#!/bin/bash
set -e

echo "=== Setting up Setup Course Badge Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Moodle web interface to be fully up
echo "Waiting for Moodle to be ready..."
for i in {1..60}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
        echo "Moodle is ready."
        break
    fi
    sleep 2
done

# Prepare the placeholder badge image for the agent
mkdir -p /home/ga/Documents
echo "Downloading realistic badge image..."
wget -qO /home/ga/Documents/hazmat_badge.png "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e4/Hazmat_Class_3_Red_Flammable_Liquid.png/240px-Hazmat_Class_3_Red_Flammable_Liquid.png" || true

# Fallback base64 image if wget fails (simple red dot png)
if [ ! -s /home/ga/Documents/hazmat_badge.png ]; then
    echo "iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAFUlEQVR42mP8z8BQz0AEYBxVSF+FAP5E/wV9xU/xAAAAAElFTkSuQmCC" | base64 -d > /home/ga/Documents/hazmat_badge.png
fi
chown -R ga:ga /home/ga/Documents

# Create the Moodle course and assignment via PHP API to ensure a clean state
cat > /tmp/setup_course.php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot.'/course/lib.php');
require_once($CFG->dirroot.'/course/modlib.php');

// 1. Check if course exists, if not create it
$course = $DB->get_record('course', ['shortname' => 'HAZ101']);
if (!$course) {
    $coursedata = new stdClass();
    $coursedata->fullname = 'Hazmat Operations';
    $coursedata->shortname = 'HAZ101';
    $coursedata->category = 1; 
    $coursedata->format = 'topics';
    $coursedata->numsections = 1;
    $coursedata->enablecompletion = 0; // Starts disabled!
    $course = create_course($coursedata);
} else {
    // Reset completion to 0 if it exists
    $course->enablecompletion = 0;
    update_course($course);
}

// 2. Check if assignment exists, if not create it
$assign = $DB->get_record('assign', ['course' => $course->id, 'name' => 'Hazmat Final Assessment']);
if (!$assign) {
    $assigndata = new stdClass();
    $assigndata->course = $course->id;
    $assigndata->name = 'Hazmat Final Assessment';
    $assigndata->intro = 'Please submit your final assessment here.';
    $assigndata->introformat = FORMAT_HTML;
    $assigndata->alwaysshowdescription = 1;
    $assigndata->submissiondrafts = 0;
    $assigndata->requiresubmissionstatement = 0;
    $assigndata->completionsubmit = 0; // Starts disabled
    $assigndata->timecreated = time();
    $assigndata->timemodified = time();
    $assigndata->id = $DB->insert_record('assign', $assigndata);

    // Course module
    $cm = new stdClass();
    $cm->course = $course->id;
    $cm->module = $DB->get_field('modules', 'id', ['name' => 'assign']);
    $cm->instance = $assigndata->id;
    $cm->section = 1;
    $cm->added = time();
    $cm->completion = 0; // Starts disabled
    $cm->id = add_course_module($cm);

    // Add to section
    $sectionid = course_add_cm_to_section($course->id, $cm->id, 1);
    $cm->section = $sectionid;
    $DB->update_record('course_modules', $cm);
}

// Clean up any existing badge to prevent pre-existing state
$DB->delete_records('badge', ['name' => 'Hazmat Operations Certified']);

rebuild_course_cache($course->id);
echo "Setup complete. Course ID: " . $course->id . "\n";
PHPEOF

echo "Running Moodle configuration..."
sudo -u www-data php /tmp/setup_course.php

# Start Firefox
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/my/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox and maximize it
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Allow UI to stabilize and take screenshot
sleep 2
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="