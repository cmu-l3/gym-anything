#!/bin/bash
echo "=== Exporting Exit Interview Result ==="

source /workspace/scripts/task_utils.sh

# Fallback query function
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the survey ID
echo "Searching for survey..."
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Employee Exit Interview 2024%' ORDER BY s.sid DESC LIMIT 1")

SURVEY_FOUND="false"
SURVEY_ACTIVE="N"
Q_NAME_CODE=""
Q_NAME_MANDATORY=""
Q_REASON_CODE=""
Q_REASON_OPTIONS=0
Q_PIPING_TEXT=""
Q_PIPING_TYPE=""

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey SID: $SID"

    # Check Active Status
    SURVEY_ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID")
    
    # 2. check Q1 (Name) - Expect Code EMPNAME
    # We look for a question with title 'EMPNAME' in this survey
    Q_NAME_DATA=$(limesurvey_query "SELECT title, mandatory FROM lime_questions WHERE sid=$SID AND title='EMPNAME'")
    if [ -n "$Q_NAME_DATA" ]; then
        Q_NAME_CODE=$(echo "$Q_NAME_DATA" | awk '{print $1}')
        Q_NAME_MANDATORY=$(echo "$Q_NAME_DATA" | awk '{print $2}')
    fi

    # 3. Check Q2 (Reason) - Expect Code REASON
    Q_REASON_DATA=$(limesurvey_query "SELECT qid, title FROM lime_questions WHERE sid=$SID AND title='REASON'")
    if [ -n "$Q_REASON_DATA" ]; then
        Q_REASON_QID=$(echo "$Q_REASON_DATA" | awk '{print $1}')
        Q_REASON_CODE=$(echo "$Q_REASON_DATA" | awk '{print $2}')
        
        # Count answers for REASON
        Q_REASON_OPTIONS=$(limesurvey_query "SELECT COUNT(*) FROM lime_answers WHERE qid=$Q_REASON_QID")
    fi

    # 4. Check Q3 (Piping) - Look for Long Free Text (T) containing syntax
    # Since we don't know the code the agent gave Q3, we search by content or type
    # We explicitly look for the specific piping syntax in ANY question text in this survey
    # Piping syntax: {REASON.shown} and {EMPNAME}
    
    # Get the question text from l10ns table where the question belongs to this SID
    # We select the question text that matches our criteria
    Q_PIPING_TEXT=$(limesurvey_query "SELECT ql.question 
        FROM lime_questions q 
        JOIN lime_question_l10ns ql ON q.qid=ql.qid 
        WHERE q.sid=$SID 
        AND (ql.question LIKE '%{REASON.shown}%' OR ql.question LIKE '%{EMPNAME}%') 
        LIMIT 1")
    
    # Also get the type of that question to verify it's Long Free Text (T) or similar
    if [ -n "$Q_PIPING_TEXT" ]; then
         # Escape quotes for sql query safety in next step? No, just find type by qid via text match logic
         # Let's just find the type associated with the text we found
         Q_PIPING_TYPE=$(limesurvey_query "SELECT q.type 
            FROM lime_questions q 
            JOIN lime_question_l10ns ql ON q.qid=ql.qid 
            WHERE q.sid=$SID 
            AND ql.question LIKE '%{REASON.shown}%' 
            LIMIT 1")
    fi
fi

# Sanitize piping text for JSON (escape double quotes)
SAFE_PIPING_TEXT=$(echo "$Q_PIPING_TEXT" | sed 's/"/\\"/g' | tr -d '\n')

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "survey_active": "$SURVEY_ACTIVE",
    "q_name_code": "$Q_NAME_CODE",
    "q_name_mandatory": "$Q_NAME_MANDATORY",
    "q_reason_code": "$Q_REASON_CODE",
    "q_reason_options": ${Q_REASON_OPTIONS:-0},
    "q_piping_text": "$SAFE_PIPING_TEXT",
    "q_piping_type": "$Q_PIPING_TYPE",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Exported JSON:"
cat /tmp/task_result.json