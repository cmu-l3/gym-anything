#!/bin/bash
echo "=== Exporting NPS Task Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definition for limesurvey_query
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the survey created by the agent
# Look for surveys created AFTER task start time or with matching title
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Find SID based on Title
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id WHERE LOWER(sl.surveyls_title) LIKE '%nps%' OR LOWER(sl.surveyls_title) LIKE '%customer experience%' ORDER BY s.datecreated DESC LIMIT 1")

SURVEY_FOUND="false"
SURVEY_INFO="{}"
QUESTIONS_JSON="[]"

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey SID: $SID"
    
    # Get Survey Settings
    ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID")
    ANONYMIZED=$(limesurvey_query "SELECT anonymized FROM lime_surveys WHERE sid=$SID")
    TITLE=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
    CREATED_DATE=$(limesurvey_query "SELECT datecreated FROM lime_surveys WHERE sid=$SID")
    
    # Check if created during task (rough check)
    # Note: datecreated is YYYY-MM-DD HH:MM:SS
    # We'll rely on the verifier to check timestamps more precisely if needed, 
    # but the setup script cleared old matching surveys, so existence is a strong signal.

    SURVEY_INFO=$(cat <<EOF
    {
        "sid": "$SID",
        "title": "$(echo $TITLE | sed 's/"/\\"/g')",
        "active": "$ACTIVE",
        "anonymized": "$ANONYMIZED",
        "created_date": "$CREATED_DATE"
    }
EOF
)

    # Get Questions
    # We need: Title (Code), Type, Mandatory, Question Text (from l10ns), Relevance, Question Order
    # Note: We need to handle potential special chars in SQL output
    
    # Create a temporary file to store question data
    TEMP_Q_FILE=$(mktemp)
    
    # Query to get raw question data. Fields: qid, title, type, mandatory, relevance, question_text
    # Using specific delimiter '|||' to help parsing
    limesurvey_query "SELECT 
        q.qid, 
        q.title, 
        q.type, 
        q.mandatory, 
        COALESCE(q.relevance, ''), 
        COALESCE(ql.question, '') 
    FROM lime_questions q 
    JOIN lime_question_l10ns ql ON q.qid = ql.qid 
    WHERE q.sid=$SID AND q.parent_qid=0 
    ORDER BY q.gid, q.question_order" > "$TEMP_Q_FILE"

    # Convert tab-separated DB output to JSON array
    # Python is safer for JSON construction than bash string manipulation
    QUESTIONS_JSON=$(python3 -c "
import sys, json
questions = []
try:
    with open('$TEMP_Q_FILE', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 6:
                questions.append({
                    'qid': parts[0],
                    'code': parts[1],
                    'type': parts[2],
                    'mandatory': parts[3],
                    'relevance': parts[4],
                    'text': parts[5]
                })
    print(json.dumps(questions))
except Exception as e:
    print('[]')
")
    rm -f "$TEMP_Q_FILE"
fi

# Construct final result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start_time": $TASK_START,
    "survey_found": $SURVEY_FOUND,
    "survey_info": $SURVEY_INFO,
    "questions": $QUESTIONS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="