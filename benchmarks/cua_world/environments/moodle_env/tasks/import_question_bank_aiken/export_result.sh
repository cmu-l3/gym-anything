#!/bin/bash
set -e
echo "=== Exporting Import Question Bank task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Execute a PHP script to query the database using Moodle's API.
# This prevents brittleness from Moodle 4.0+ Question Bank schema changes
# (which split questions across mdl_question, mdl_question_bank_entries, mdl_question_versions).

cat > /tmp/export_questions.php << 'PHPEOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');
global $DB;

$course = $DB->get_record('course', array('shortname'=>'NURS101'), '*', IGNORE_MISSING);

$result = array(
    'course_exists' => false,
    'target_category_exists' => false,
    'target_category_q_count' => 0,
    'total_course_q_count' => 0,
    'sample_question_text' => "",
    'file_modified_time' => 0,
    'screenshot_exists' => file_exists('/tmp/task_final.png')
);

if ($course) {
    $result['course_exists'] = true;
    $context = context_course::instance($course->id);
    
    // Fetch all categories in this course context
    $categories = $DB->get_records('question_categories', array('contextid'=>$context->id));
    
    foreach($categories as $cat) {
        $cat_name = trim(strtolower($cat->name));
        $is_target = ($cat_name === 'cardiology nclex review');
        
        if ($is_target) {
            $result['target_category_exists'] = true;
        }
        
        $cat_q_count = 0;
        
        // Moodle 4.0+ uses question_bank_entries
        if ($DB->get_manager()->table_exists('question_bank_entries')) {
            $cat_q_count = $DB->count_records('question_bank_entries', array('questioncategoryid'=>$cat->id));
            
            // Extract a sample question text to prove Aiken import worked (not manual dummy data)
            if ($cat_q_count > 0 && empty($result['sample_question_text'])) {
                $sql = "SELECT q.questiontext FROM {question} q 
                        JOIN {question_versions} qv ON q.id = qv.questionid 
                        JOIN {question_bank_entries} qbe ON qv.questionbankentryid = qbe.id 
                        WHERE qbe.questioncategoryid = ?";
                $records = $DB->get_records_sql($sql, array($cat->id), 0, 1);
                if (!empty($records)) {
                    $result['sample_question_text'] = reset($records)->questiontext;
                }
            }
        } else {
            // Pre-Moodle 4.0 fallback
            $cat_q_count = $DB->count_records('question', array('category'=>$cat->id));
            if ($cat_q_count > 0 && empty($result['sample_question_text'])) {
                $records = $DB->get_records('question', array('category'=>$cat->id), '', 'questiontext', 0, 1);
                if (!empty($records)) {
                    $result['sample_question_text'] = reset($records)->questiontext;
                }
            }
        }
        
        if ($is_target) {
            $result['target_category_q_count'] += $cat_q_count;
        }
        $result['total_course_q_count'] += $cat_q_count;
    }
}

// Check the timestamp of the source file to see if the agent interacted with it
if (file_exists('/home/ga/Desktop/cardiology_nclex_questions.txt')) {
    $result['file_modified_time'] = filemtime('/home/ga/Desktop/cardiology_nclex_questions.txt');
}

echo json_encode($result);
PHPEOF

# Execute the PHP script as www-data to avoid permission issues
sudo -u www-data php /tmp/export_questions.php > /tmp/task_result.json

echo "Exported results:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="