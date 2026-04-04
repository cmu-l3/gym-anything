#!/bin/bash
# Export script for BIO101 Final Exam Configuration task

echo "=== Exporting BIO101 Final Exam Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Gather context
COURSE_ID=$(cat /tmp/bio101_course_id 2>/dev/null || echo "")
START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
END_TIME=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_quiz_count 2>/dev/null || echo "0")

if [ -z "$COURSE_ID" ]; then
    # Emergency fallback lookup
    COURSE_ID=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='bio101' LIMIT 1")
fi

# 3. Query the Quiz Data
# We look for a quiz created/updated AFTER the task started in BIO101 with the correct title
# Using a custom separator |^| to handle potential pipes in descriptions
SEPARATOR="|^|"

# Note: We query for the SPECIFIC title required.
QUIZ_DATA=$(canvas_query "SELECT id, title, quiz_type, time_limit, allowed_attempts, access_code, shuffle_answers, one_question_at_a_time, due_at, unlock_at, lock_at, workflow_state, description, created_at FROM quizzes WHERE context_id='$COURSE_ID' AND context_type='Course' AND LOWER(TRIM(title))='bio101 final examination' AND workflow_state != 'deleted' ORDER BY id DESC LIMIT 1" | sed "s/|/$SEPARATOR/g")

# If standard query fails (maybe title is slightly off?), get the most recent quiz in the course
if [ -z "$QUIZ_DATA" ]; then
    echo "Exact title match not found. Checking most recent quiz..."
    LATEST_QUIZ=$(canvas_query "SELECT id, title, quiz_type, time_limit, allowed_attempts, access_code, shuffle_answers, one_question_at_a_time, due_at, unlock_at, lock_at, workflow_state, description, created_at FROM quizzes WHERE context_id='$COURSE_ID' AND context_type='Course' AND workflow_state != 'deleted' ORDER BY id DESC LIMIT 1" | sed "s/|/$SEPARATOR/g")
    
    # We will export this, and the verifier will punish the wrong title
    QUIZ_DATA="$LATEST_QUIZ"
fi

# 4. Get Current Count
CURRENT_COUNT=$(canvas_query "SELECT COUNT(*) FROM quizzes WHERE context_id='$COURSE_ID' AND context_type='Course' AND workflow_state != 'deleted'")

# 5. Construct JSON Result
# We use Python to robustly construct the JSON to avoid bash quoting hell
python3 -c "
import json
import sys
import os

try:
    raw_data = '''$QUIZ_DATA'''
    sep = '''$SEPARATOR'''
    
    result = {
        'task_start': $START_TIME,
        'task_end': $END_TIME,
        'course_id': '$COURSE_ID',
        'initial_count': int('$INITIAL_COUNT'),
        'current_count': int('$CURRENT_COUNT'),
        'quiz_found': False,
        'quiz': {}
    }

    if raw_data and raw_data.strip():
        parts = raw_data.strip().split(sep)
        # Expected columns: id, title, quiz_type, time_limit, allowed_attempts, access_code, 
        # shuffle_answers, one_question_at_a_time, due_at, unlock_at, lock_at, workflow_state, 
        # description, created_at
        
        if len(parts) >= 14:
            result['quiz_found'] = True
            result['quiz'] = {
                'id': parts[0],
                'title': parts[1],
                'quiz_type': parts[2],
                'time_limit': parts[3],
                'allowed_attempts': parts[4],
                'access_code': parts[5],
                'shuffle_answers': parts[6],
                'one_question_at_a_time': parts[7],
                'due_at': parts[8],
                'unlock_at': parts[9],
                'lock_at': parts[10],
                'workflow_state': parts[11],
                'description': parts[12],
                'created_at': parts[13]
            }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    print(f'Error constructing JSON: {e}', file=sys.stderr)
    # Fallback empty JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# 6. Secure the output file
chmod 666 /tmp/task_result.json

echo "JSON result generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="