#!/bin/bash
set -e

echo "=== Exporting Course Badge Task Results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract Moodle state to JSON using PHP
# This safely checks the internal relational state of badges and completions
cat > /tmp/export_state.php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');

$task_start = intval(file_get_contents('/tmp/task_start_time.txt'));

$result = [
    'task_start' => $task_start,
    'export_time' => time(),
    'course_exists' => false,
    'course_completion_enabled' => false,
    'assign_exists' => false,
    'assign_completion_enabled' => false,
    'assign_completion_submit' => false,
    'badge_exists' => false,
    'badge_active' => false,
    'badge_created_during_task' => false,
    'badge_criteria_activity' => false,
    'badge_criteria_correct_module' => false
];

// 1. Get Course
$course = $DB->get_record('course', ['shortname' => 'HAZ101']);
if ($course) {
    $result['course_exists'] = true;
    $result['course_completion_enabled'] = ($course->enablecompletion == 1);

    // 2. Get Assignment & Module
    $assign = $DB->get_record('assign', ['course' => $course->id, 'name' => 'Hazmat Final Assessment']);
    if ($assign) {
        $result['assign_exists'] = true;
        $result['assign_completion_submit'] = ($assign->completionsubmit == 1);

        $module_id = $DB->get_field('modules', 'id', ['name' => 'assign']);
        $cm = $DB->get_record('course_modules', ['course' => $course->id, 'instance' => $assign->id, 'module' => $module_id]);
        
        if ($cm) {
            $result['assign_completion_enabled'] = ($cm->completion == 2); // 2 = COMPLETION_TRACKING_AUTOMATIC

            // 3. Get Badge
            $badge = $DB->get_record('badge', ['courseid' => $course->id, 'name' => 'Hazmat Operations Certified']);
            if ($badge) {
                $result['badge_exists'] = true;
                $result['badge_active'] = ($badge->status == 1 || $badge->status == 3); // 1 = active, 3 = active+locked
                $result['badge_created_during_task'] = ($badge->timecreated >= ($task_start - 5));

                // 4. Get Badge Criteria
                // 4 = BADGE_CRITERIA_TYPE_ACTIVITY
                $criteria = $DB->get_record('badge_criteria', ['badgeid' => $badge->id, 'criteriatype' => 4]);
                if ($criteria) {
                    $result['badge_criteria_activity'] = true;

                    // 5. Get Criteria Parameter (must point to our assignment cmid)
                    $params = $DB->get_records('badge_criteria_param', ['critid' => $criteria->id]);
                    foreach ($params as $param) {
                        if (strpos($param->name, 'module_') === 0 && $param->value == $cm->id) {
                            $result['badge_criteria_correct_module'] = true;
                            break;
                        }
                    }
                }
            }
        }
    }
}

file_put_contents('/tmp/task_result.json', json_encode($result, JSON_PRETTY_PRINT));
PHPEOF

echo "Extracting database state..."
sudo -u www-data php /tmp/export_state.php

# Fix permissions so verifier can copy it
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="