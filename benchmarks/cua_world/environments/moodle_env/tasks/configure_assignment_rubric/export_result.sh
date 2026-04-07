#!/bin/bash
set -e
echo "=== Exporting Configure Assignment Rubric Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract Rubric Configuration via Moodle API
echo "Extracting database records..."
cat > /tmp/export_rubric_data.php << 'PHP_EOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
global $DB;

$result = ['found' => false];

$assign = $DB->get_record('assign', ['name' => 'Final Analytical Essay']);
if ($assign) {
    $cm = $DB->get_record('course_modules', ['instance' => $assign->id, 'module' => $DB->get_field('modules', 'id', ['name' => 'assign'])]);
    if ($cm) {
        $context = context_module::instance($cm->id);
        $area = $DB->get_record('grading_areas', ['contextid' => $context->id, 'component' => 'mod_assign', 'areaname' => 'submissions']);
        
        if ($area) {
            $result['found'] = true;
            $result['activemethod'] = $area->activemethod;
            
            $definition = $DB->get_record('grading_definitions', ['areaid' => $area->id, 'method' => 'rubric']);
            if ($definition) {
                $result['definition'] = [
                    'name' => $definition->name,
                    'status' => $definition->status,
                    'timecreated' => $definition->timecreated,
                    'timemodified' => $definition->timemodified,
                    'criteria' => []
                ];
                
                $criteria = $DB->get_records('gradingform_rubric_criteria', ['definitionid' => $definition->id]);
                foreach ($criteria as $c) {
                    $crit_data = [
                        'description' => $c->description,
                        'levels' => []
                    ];
                    $levels = $DB->get_records('gradingform_rubric_levels', ['criterionid' => $c->id]);
                    foreach ($levels as $l) {
                        $crit_data['levels'][] = [
                            'score' => $l->score,
                            'definition' => $l->definition
                        ];
                    }
                    $result['definition']['criteria'][] = $crit_data;
                }
            }
        }
    }
}
echo json_encode($result);
PHP_EOF

# Run PHP export script and save output
sudo -u www-data php /tmp/export_rubric_data.php > /tmp/moodle_rubric_data.json

# Combine timing and database data into final JSON
cat > /tmp/merge_results.py << 'PY_EOF'
import json

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

with open('/tmp/moodle_rubric_data.json', 'r') as f:
    db_data = json.load(f)

final_data = {
    "task_start": task_start,
    "moodle_data": db_data
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_data, f, indent=4)
PY_EOF

python3 /tmp/merge_results.py
chmod 666 /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="