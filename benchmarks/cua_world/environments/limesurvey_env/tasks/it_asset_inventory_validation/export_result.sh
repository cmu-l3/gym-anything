#!/bin/bash
echo "=== Exporting IT Asset Inventory Validation Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Find the Survey
# We look for the specific title created AFTER the task started (by checking creation date or just existence if it didn't exist before)
# Since we can't easily check creation timestamp down to the second in simple SQL without parsing, we'll look for the title.
SURVEY_TITLE="IT Asset Audit 2025"
echo "Searching for survey: $SURVEY_TITLE"

SURVEY_ID=$(get_survey_id "$SURVEY_TITLE")

SURVEY_FOUND="false"
QUESTIONS_DATA="[]"

if [ -n "$SURVEY_ID" ] && [ "$SURVEY_ID" != "NULL" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey ID: $SURVEY_ID"

    # 2. Extract Question Data
    # We need: Title (Code), Question Text, Type, Preg (Regex), Help (Tip), and Attributes (for logic)
    # Note: Logic equations are stored in lime_question_attributes with attribute='em_validation_q'
    
    # We will build a JSON array of questions manually or via python helper
    
    QUESTIONS_JSON=$(python3 -c "
import mysql.connector
import json
import sys

try:
    conn = mysql.connector.connect(
        host='limesurvey-db',
        user='limesurvey',
        password='limesurvey_pass',
        database='limesurvey'
    )
    cursor = conn.cursor(dictionary=True)
    
    sid = $SURVEY_ID
    
    # Get questions
    query_q = \"\"\"
    SELECT q.qid, q.title as code, q.type, q.preg, l.help, l.question
    FROM lime_questions q
    JOIN lime_questions_l10ns l ON q.qid = l.qid
    WHERE q.sid = %s
    \"\"\"
    cursor.execute(query_q, (sid,))
    questions = cursor.fetchall()
    
    # Get attributes for these questions (specifically em_validation_q)
    for q in questions:
        query_a = \"\"\"
        SELECT value 
        FROM lime_question_attributes 
        WHERE qid = %s AND attribute = 'em_validation_q'
        \"\"\"
        cursor.execute(query_a, (q['qid'],))
        attr = cursor.fetchone()
        q['validation_equation'] = attr['value'] if attr else ''
        
        # Clean strings
        if q['preg'] is None: q['preg'] = ''
        if q['help'] is None: q['help'] = ''
        if q['validation_equation'] is None: q['validation_equation'] = ''

    print(json.dumps(questions))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))
")
    
    QUESTIONS_DATA="$QUESTIONS_JSON"
else
    echo "Survey not found."
fi

# Create final JSON result
cat > /tmp/task_result.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "survey_id": "$SURVEY_ID",
    "questions": $QUESTIONS_DATA,
    "task_start": $TASK_START,
    "export_time": $(date +%s)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json