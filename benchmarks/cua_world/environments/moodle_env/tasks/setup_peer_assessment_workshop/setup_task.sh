#!/bin/bash
echo "=== Setting up Peer Assessment Workshop Task ==="
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Create the Nursing Ethics course using Moodle PHP CLI
echo "Creating Nursing Ethics and Law course..."
cat > /tmp/create_course.php << 'EOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
require_once($CFG->dirroot.'/course/lib.php');

$category = $DB->get_record('course_categories', array(), '*', IGNORE_MULTIPLE);
$catid = $category ? $category->id : 1;

if (!$course = $DB->get_record('course', array('shortname' => 'NURSE_ETHICS'))) {
    $coursedata = new stdClass();
    $coursedata->fullname = 'Nursing Ethics and Law';
    $coursedata->shortname = 'NURSE_ETHICS';
    $coursedata->category = $catid;
    $coursedata->summary = 'A course on ethical dilemmas in nursing practice.';
    $coursedata->visible = 1;
    $course = create_course($coursedata);
    echo $course->id;
} else {
    echo $course->id;
}
EOF

sudo -u www-data php /tmp/create_course.php > /tmp/course_creation.log
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='NURSE_ETHICS'" | head -n 1)
echo "$COURSE_ID" > /tmp/course_id.txt

# Record initial workshop count
INITIAL_WORKSHOPS=$(moodle_query "SELECT COUNT(*) FROM mdl_workshop" | head -n 1)
echo "${INITIAL_WORKSHOPS:-0}" > /tmp/initial_workshop_count.txt

# 2. Create the setup document for the agent
echo "Generating ethics_workshop_setup.txt..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/ethics_workshop_setup.txt << 'EOF'
Workshop Name: Peer Assessment: End-of-Life Care Scenario

Submission Instructions:
Read the provided clinical scenario regarding the 85-year-old patient with Alzheimer's and pneumonia. Write a 500-word analysis identifying the primary ethical dilemma, focusing on patient autonomy versus medical beneficence.

Assessment Instructions:
Evaluate your peer's analysis using the accumulative grading rubric. Provide constructive, professional feedback for each aspect to help them improve their clinical reasoning.

Grading Strategy: Accumulative grading

Grading Aspects:
1. Aspect: Autonomy
   Maximum Grade: 30
   Description: Did the author correctly identify and respect the patient's prior wishes and autonomy?

2. Aspect: Beneficence/Non-maleficence
   Maximum Grade: 40
   Description: Did the author adequately weigh the benefits of treatment against the potential harm and suffering?

3. Aspect: Clarity
   Maximum Grade: 30
   Description: Is the analysis well-structured, professional, and clear?
EOF
chown ga:ga /home/ga/Documents/ethics_workshop_setup.txt

# 3. Start Firefox
echo "Starting Firefox and navigating to login..."
restart_firefox "http://localhost/login/index.php"

# Wait for browser to be ready and grab a screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="