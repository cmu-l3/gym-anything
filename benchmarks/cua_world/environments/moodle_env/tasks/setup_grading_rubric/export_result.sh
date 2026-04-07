#!/bin/bash
echo "=== Exporting setup_grading_rubric task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# Initialize variables
COURSE_ID=""
ASSIGN_ID=""
CM_ID=""
CONTEXT_ID=""
ACTIVE_METHOD="null"
AREA_ID=""
DEF_ID=""
RUBRIC_NAME="null"
RUBRIC_STATUS="0"
CRITERIA_COUNT="0"
MAX_POINTS="0"
TIME_MODIFIED="0"

# 1. Gather data carefully step-by-step to avoid empty query failures
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname = 'PSY101' LIMIT 1" || echo "")

if [ -n "$COURSE_ID" ]; then
    ASSIGN_ID=$(moodle_query "SELECT id FROM mdl_assign WHERE course = '$COURSE_ID' AND name = 'Final Research Paper' LIMIT 1" || echo "")
    
    if [ -n "$ASSIGN_ID" ]; then
        CM_ID=$(moodle_query "SELECT cm.id FROM mdl_course_modules cm JOIN mdl_modules m ON m.id = cm.module WHERE cm.course = '$COURSE_ID' AND cm.instance = '$ASSIGN_ID' AND m.name = 'assign' LIMIT 1" || echo "")
        
        if [ -n "$CM_ID" ]; then
            CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel = 70 AND instanceid = '$CM_ID' LIMIT 1" || echo "")
            
            if [ -n "$CONTEXT_ID" ]; then
                ACTIVE_METHOD=$(moodle_query "SELECT activemethod FROM mdl_grading_areas WHERE contextid = '$CONTEXT_ID' AND component = 'mod_assign' AND areaname = 'submissions' LIMIT 1" || echo "null")
                AREA_ID=$(moodle_query "SELECT id FROM mdl_grading_areas WHERE contextid = '$CONTEXT_ID' AND component = 'mod_assign' AND areaname = 'submissions' LIMIT 1" || echo "")
                
                if [ -n "$AREA_ID" ]; then
                    DEF_ID=$(moodle_query "SELECT id FROM mdl_grading_definitions WHERE areaid = '$AREA_ID' ORDER BY timemodified DESC LIMIT 1" || echo "")
                    
                    if [ -n "$DEF_ID" ]; then
                        RUBRIC_NAME=$(moodle_query "SELECT name FROM mdl_grading_definitions WHERE id = '$DEF_ID'" || echo "null")
                        RUBRIC_STATUS=$(moodle_query "SELECT status FROM mdl_grading_definitions WHERE id = '$DEF_ID'" || echo "0")
                        TIME_MODIFIED=$(moodle_query "SELECT timemodified FROM mdl_grading_definitions WHERE id = '$DEF_ID'" || echo "0")
                        CRITERIA_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_gradingform_rubric_criteria WHERE definitionid = '$DEF_ID'" || echo "0")
                        MAX_POINTS=$(moodle_query "SELECT SUM(max_score) FROM (SELECT criterionid, MAX(score) as max_score FROM mdl_gradingform_rubric_levels WHERE criterionid IN (SELECT id FROM mdl_gradingform_rubric_criteria WHERE definitionid = '$DEF_ID') GROUP BY criterionid) as t" || echo "0")
                    fi
                fi
            fi
        fi
    fi
fi

# 2. Get the task start time for anti-gaming checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Create JSON output safely using Python
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
data = {
    'task_start': $TASK_START,
    'active_method': '$ACTIVE_METHOD',
    'rubric_name': '''$RUBRIC_NAME''',
    'rubric_status': int('$RUBRIC_STATUS') if '$RUBRIC_STATUS'.isdigit() else 0,
    'criteria_count': int('$CRITERIA_COUNT') if '$CRITERIA_COUNT'.isdigit() else 0,
    'max_points': float('$MAX_POINTS') if '$MAX_POINTS' and '$MAX_POINTS' != 'null' else 0,
    'time_modified': int('$TIME_MODIFIED') if '$TIME_MODIFIED'.isdigit() else 0,
    'document_accessed': True  # Defaulting here, checked in verifier
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f, indent=4)
"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="