#!/bin/bash
echo "=== Exporting Configure Branching Lesson result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if firefox was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Run PHP script to extract Lesson details robustly from the Moodle database
echo "Extracting Lesson configuration from database..."
cat > /tmp/export_lesson.php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');

$result = new stdClass();
$result->lesson_exists = false;
$result->lesson = null;
$result->pages = [];
$result->answers = [];
$result->files = [];
$result->course_exists = false;

// Find course
$course = $DB->get_record('course', ['shortname' => 'HAZMAT101']);
if ($course) {
    $result->course_exists = true;
}

// Find lesson
$lesson = $DB->get_record('lesson', ['name' => 'Initial Isolation and Protective Action'], '*', IGNORE_MULTIPLE);

if ($lesson) {
    $result->lesson_exists = true;
    $result->lesson = $lesson;
    
    // Get pages
    $pages = $DB->get_records('lesson_pages', ['lessonid' => $lesson->id], 'id ASC');
    foreach ($pages as $p) {
        $result->pages[] = $p;
    }
    
    // Get answers
    $answers = $DB->get_records('lesson_answers', ['lessonid' => $lesson->id], 'id ASC');
    foreach ($answers as $a) {
        $result->answers[] = $a;
    }
    
    // Get files for this lesson (context)
    $cm = get_coursemodule_from_instance('lesson', $lesson->id);
    if ($cm) {
        $context = context_module::instance($cm->id);
        $files = $DB->get_records('files', ['contextid' => $context->id, 'component' => 'mod_lesson', 'filearea' => 'page_contents']);
        foreach ($files as $f) {
            if ($f->filename !== '.') {
                $result->files[] = $f;
            }
        }
    }
}

echo json_encode($result);
PHPEOF

sudo -u www-data php /tmp/export_lesson.php > /tmp/lesson_data.json

# Merge PHP output with task metadata securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

try:
    with open('/tmp/lesson_data.json', 'r') as f:
        data = json.load(f)
except Exception as e:
    data = {'error': str(e)}

data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
data['app_was_running'] = str('$APP_RUNNING').lower() == 'true'

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"

# Copy to final location allowing verifier read access
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result successfully exported to /tmp/task_result.json"
echo "=== Export complete ==="