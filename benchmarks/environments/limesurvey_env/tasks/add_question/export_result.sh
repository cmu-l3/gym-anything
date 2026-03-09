#!/bin/bash
echo "=== Exporting Add Question Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get survey ID
SURVEY_ID=$(cat /tmp/task_survey_id 2>/dev/null || echo "")
INITIAL=$(cat /tmp/initial_question_count 2>/dev/null || echo "0")
CURRENT=$(get_question_count "$SURVEY_ID")

echo "Question count: initial=$INITIAL, current=$CURRENT"

# Debug: Show all questions in database for this survey
echo ""
echo "=== DEBUG: All questions in survey $SURVEY_ID ==="
limesurvey_query "SELECT q.qid, q.title, ql.question, q.type FROM lime_questions q LEFT JOIN lime_question_l10ns ql ON q.qid=ql.qid WHERE q.sid=$SURVEY_ID AND q.parent_qid=0" 2>/dev/null || echo "(database query failed)"
echo "=== END DEBUG ==="

# Check for the expected question (Q_AGE with 'age' in question text)
echo ""
echo "Checking for question with code 'Q_AGE'..."
QUESTION_DATA=$(limesurvey_query "SELECT q.qid, q.title, ql.question, q.type
FROM lime_questions q
LEFT JOIN lime_question_l10ns ql ON q.qid=ql.qid
WHERE q.sid=$SURVEY_ID
AND q.parent_qid=0
AND (LOWER(q.title) LIKE '%age%' OR LOWER(ql.question) LIKE '%age%')
ORDER BY q.qid DESC
LIMIT 1")

FOUND="false"
QUESTION_ID=""
QUESTION_CODE=""
QUESTION_TEXT=""
QUESTION_TYPE=""

if [ -n "$QUESTION_DATA" ]; then
    FOUND="true"
    QUESTION_ID=$(echo "$QUESTION_DATA" | awk '{print $1}')
    QUESTION_CODE=$(echo "$QUESTION_DATA" | awk '{print $2}')
    # Get full question text from l10ns table
    QUESTION_TEXT=$(limesurvey_query "SELECT question FROM lime_question_l10ns WHERE qid=$QUESTION_ID" | head -1)
    QUESTION_TYPE=$(echo "$QUESTION_DATA" | awk '{print $NF}')
    echo "Found question: ID=$QUESTION_ID, Code=$QUESTION_CODE, Type=$QUESTION_TYPE"
else
    echo "Question with 'age' not found"

    # Try broader search for any new question
    echo "Trying broader search for any new question..."
    if [ "$CURRENT" -gt "$INITIAL" ]; then
        QUESTION_DATA=$(limesurvey_query "SELECT q.qid, q.title, ql.question, q.type
FROM lime_questions q
LEFT JOIN lime_question_l10ns ql ON q.qid=ql.qid
WHERE q.sid=$SURVEY_ID AND q.parent_qid=0
ORDER BY q.qid DESC
LIMIT 1")
        if [ -n "$QUESTION_DATA" ]; then
            FOUND="true"
            QUESTION_ID=$(echo "$QUESTION_DATA" | awk '{print $1}')
            QUESTION_CODE=$(echo "$QUESTION_DATA" | awk '{print $2}')
            QUESTION_TEXT=$(limesurvey_query "SELECT question FROM lime_question_l10ns WHERE qid=$QUESTION_ID" | head -1)
            QUESTION_TYPE=$(echo "$QUESTION_DATA" | awk '{print $NF}')
            echo "Found newest question: ID=$QUESTION_ID, Code=$QUESTION_CODE"
        fi
    fi
fi

# Create JSON result
JSON_CONTENT=$(cat << EOF
{
    "survey_id": "$SURVEY_ID",
    "initial_question_count": $INITIAL,
    "current_question_count": $CURRENT,
    "question_found": $FOUND,
    "question": {
        "question_id": "$QUESTION_ID",
        "code": "$QUESTION_CODE",
        "text": "$QUESTION_TEXT",
        "type": "$QUESTION_TYPE"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

export_json_result "$JSON_CONTENT" "/tmp/add_question_result.json"

echo ""
cat /tmp/add_question_result.json
echo ""
echo "=== Export Complete ==="
