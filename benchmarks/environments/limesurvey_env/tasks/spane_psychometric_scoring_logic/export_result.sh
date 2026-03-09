#!/bin/bash
echo "=== Exporting SPANE Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the target survey
# Looking for "Well-being Study 2025" or similar
SURVEY_INFO=$(limesurvey_query "SELECT s.sid, s.format, sl.surveyls_title, s.active 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
WHERE sl.surveyls_title LIKE '%Well-being%' 
ORDER BY s.datecreated DESC LIMIT 1")

SID=""
FORMAT=""
TITLE=""
ACTIVE=""

if [ -n "$SURVEY_INFO" ]; then
    SID=$(echo "$SURVEY_INFO" | awk '{print $1}')
    FORMAT=$(echo "$SURVEY_INFO" | awk '{print $2}')
    # Extract title carefully (might have spaces)
    # The query output format is tab separated: SID \t FORMAT \t TITLE \t ACTIVE
    TITLE=$(echo "$SURVEY_INFO" | cut -f3)
    ACTIVE=$(echo "$SURVEY_INFO" | awk '{print $NF}')
fi

echo "Found Survey: SID=$SID, Format=$FORMAT, Active=$ACTIVE"

# 2. Extract Questions Data
QUESTIONS_JSON="[]"
if [ -n "$SID" ]; then
    # Get all questions with their codes, types, and parent IDs
    # We join with l10ns to get the question text/equation logic
    # Note: For Equation questions, the 'question' field contains the logic
    QUERY="SELECT q.qid, q.title, q.type, q.parent_qid, ql.question 
           FROM lime_questions q 
           JOIN lime_question_l10ns ql ON q.qid = ql.qid 
           WHERE q.sid = $SID"
    
    # We use python to run the query and format as JSON to handle special chars/newlines in equations
    QUESTIONS_JSON=$(python3 -c "
import mysql.connector, json
try:
    conn = mysql.connector.connect(user='limesurvey', password='limesurvey_pass', host='limesurvey-db', database='limesurvey')
    cursor = conn.cursor(dictionary=True)
    cursor.execute(\"\"\"$QUERY\"\"\")
    rows = cursor.fetchall()
    print(json.dumps(rows))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")
fi

# 3. Extract Answer Options (to verify 1-5 scale)
ANSWERS_JSON="[]"
if [ -n "$SID" ]; then
    # We just need to check if answer options exist for the array questions
    # Get QIDs of SPANEP/SPANEN (assuming titles are used)
    ANSWERS_JSON=$(python3 -c "
import mysql.connector, json
try:
    conn = mysql.connector.connect(user='limesurvey', password='limesurvey_pass', host='limesurvey-db', database='limesurvey')
    cursor = conn.cursor(dictionary=True)
    cursor.execute(\"\"\"
        SELECT a.qid, a.code, al.answer 
        FROM lime_answers a 
        JOIN lime_answer_l10ns al ON a.qid = al.qid 
        JOIN lime_questions q ON a.qid = q.qid
        WHERE q.sid = $SID
    \"\"\")
    rows = cursor.fetchall()
    print(json.dumps(rows))
except Exception as e:
    print('[]')
")
fi

# 4. Construct Final JSON
cat > /tmp/task_result_temp.json << EOF
{
    "survey_found": $([ -n "$SID" ] && echo "true" || echo "false"),
    "survey_sid": "$SID",
    "survey_format": "$FORMAT",
    "survey_active": "$ACTIVE",
    "questions": $QUESTIONS_JSON,
    "answers": $ANSWERS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
export_json_result "$(cat /tmp/task_result_temp.json)" "/tmp/task_result.json"

echo "Export complete. Result summary:"
grep "survey_found" /tmp/task_result.json