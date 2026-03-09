#!/bin/bash
echo "=== Exporting Intake Form Validation Result ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper to run SQL
run_sql() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# 1. Find the survey ID (look for CARDIA or Intake Form created recently)
echo "Searching for survey..."
SURVEY_ID=$(run_sql "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id WHERE (LOWER(sl.surveyls_title) LIKE '%cardia%' OR LOWER(sl.surveyls_title) LIKE '%intake form%') ORDER BY s.datecreated DESC LIMIT 1")

SURVEY_FOUND="false"
SURVEY_ACTIVE="N"
GROUP_COUNT=0
QUESTION_COUNT=0
QUESTIONS_JSON="[]"

if [ -n "$SURVEY_ID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey ID: $SURVEY_ID"

    # Check Active Status
    SURVEY_ACTIVE=$(run_sql "SELECT active FROM lime_surveys WHERE sid=$SURVEY_ID")
    
    # Check Group Count
    GROUP_COUNT=$(run_sql "SELECT COUNT(*) FROM lime_groups WHERE sid=$SURVEY_ID")
    
    # Check Question Count (parent questions only)
    QUESTION_COUNT=$(run_sql "SELECT COUNT(*) FROM lime_questions WHERE sid=$SURVEY_ID AND parent_qid=0")
    
    # Extract Question Details & Attributes
    # We construct a complex JSON object of questions using Python for safer parsing
    QUESTIONS_JSON=$(python3 -c "
import json
import subprocess

def run_query(query):
    cmd = ['docker', 'exec', 'limesurvey-db', 'mysql', '-u', 'limesurvey', '-plimesurvey_pass', 'limesurvey', '-N', '-e', query]
    try:
        res = subprocess.check_output(cmd).decode('utf-8').strip()
        return res
    except:
        return ''

sid = '$SURVEY_ID'
q_data = []

# Get all questions: qid, title(code), type, mandatory
q_rows = run_query(f'SELECT qid, title, type, mandatory FROM lime_questions WHERE sid={sid} AND parent_qid=0').split('\n')

for row in q_rows:
    if not row: continue
    parts = row.split('\t')
    if len(parts) < 4: continue
    
    qid, code, qtype, mandatory = parts
    
    # Get attributes for this question
    attrs = {}
    attr_rows = run_query(f'SELECT attribute, value FROM lime_question_attributes WHERE qid={qid}').split('\n')
    for a_row in attr_rows:
        if not a_row: continue
        a_parts = a_row.split('\t')
        if len(a_parts) >= 2:
            attrs[a_parts[0]] = a_parts[1]
            
    q_data.append({
        'qid': qid,
        'code': code,
        'type': qtype,
        'mandatory': mandatory,
        'attributes': attrs
    })

print(json.dumps(q_data))
")
else
    echo "Survey not found."
fi

# Create result JSON
cat > /tmp/task_result_temp.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "survey_found": $SURVEY_FOUND,
    "survey_id": "$SURVEY_ID",
    "active": "$SURVEY_ACTIVE",
    "group_count": $GROUP_COUNT,
    "question_count": $QUESTION_COUNT,
    "questions": $QUESTIONS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
export_json_result "$(cat /tmp/task_result_temp.json)" "/tmp/task_result.json"
rm -f /tmp/task_result_temp.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="