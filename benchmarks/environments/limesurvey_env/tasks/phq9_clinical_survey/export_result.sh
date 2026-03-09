#!/bin/bash
echo "=== Exporting PHQ-9 Clinical Survey Result ==="

source /workspace/scripts/task_utils.sh

if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

INITIAL_COUNT=$(cat /tmp/phq9_initial_survey_count 2>/dev/null || echo "0")
INITIAL_COUNT=${INITIAL_COUNT:-0}

# Find PHQ-9 survey
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%phq%' OR LOWER(ls.surveyls_title) LIKE '%mental health screening%' LIMIT 1" 2>/dev/null || echo "")

SURVEY_FOUND="false"
SURVEY_TITLE=""
SURVEY_ACTIVE="N"
SURVEY_ANONYMIZED="N"
GROUP_COUNT=0
TOTAL_QUESTION_COUNT=0
ARRAY_QUESTION_COUNT=0
ARRAY_SUBQUESTION_COUNT=0
MANDATORY_QUESTION_COUNT=0
HAS_RELEVANCE_CONDITION="false"
ANSWER_COUNT=0
CURRENT_SURVEY_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys" 2>/dev/null || echo "0")
CURRENT_SURVEY_COUNT=${CURRENT_SURVEY_COUNT:-0}

if [ -n "$SID" ] && [ "$SID" != "NULL" ]; then
    SURVEY_FOUND="true"
    SURVEY_TITLE=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID LIMIT 1" 2>/dev/null || echo "")
    SURVEY_ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID" 2>/dev/null || echo "N")
    SURVEY_ACTIVE=${SURVEY_ACTIVE:-N}
    SURVEY_ANONYMIZED=$(limesurvey_query "SELECT anonymized FROM lime_surveys WHERE sid=$SID" 2>/dev/null || echo "N")
    SURVEY_ANONYMIZED=${SURVEY_ANONYMIZED:-N}

    # Count question groups
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID" 2>/dev/null || echo "0")
    GROUP_COUNT=${GROUP_COUNT:-0}

    # Count parent questions (exclude sub-questions)
    TOTAL_QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0" 2>/dev/null || echo "0")
    TOTAL_QUESTION_COUNT=${TOTAL_QUESTION_COUNT:-0}

    # Count array questions (type F = 5-point array, H = array by column, etc.)
    ARRAY_QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0 AND type IN ('F','H','1','A','B','C','E')" 2>/dev/null || echo "0")
    ARRAY_QUESTION_COUNT=${ARRAY_QUESTION_COUNT:-0}

    # Find sub-questions of array questions
    ARRAY_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND parent_qid=0 AND type IN ('F','H','1','A','B','C','E') ORDER BY question_order LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$ARRAY_QID" ]; then
        ARRAY_SUBQUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE parent_qid=$ARRAY_QID" 2>/dev/null || echo "0")
        ARRAY_SUBQUESTION_COUNT=${ARRAY_SUBQUESTION_COUNT:-0}
    fi

    # Count mandatory questions
    MANDATORY_QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0 AND mandatory='Y'" 2>/dev/null || echo "0")
    MANDATORY_QUESTION_COUNT=${MANDATORY_QUESTION_COUNT:-0}

    # Check answer options for the array question (PHQ-9 needs 4 options)
    if [ -n "$ARRAY_QID" ]; then
        ANSWER_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_answers WHERE qid=$ARRAY_QID" 2>/dev/null || echo "0")
        ANSWER_COUNT=${ANSWER_COUNT:-0}
    fi

    echo "SID=$SID, Title=$SURVEY_TITLE, Active=$SURVEY_ACTIVE, Anonymized=$SURVEY_ANONYMIZED"
    echo "Groups=$GROUP_COUNT, Questions=$TOTAL_QUESTION_COUNT, ArrayQs=$ARRAY_QUESTION_COUNT, ArraySubQs=$ARRAY_SUBQUESTION_COUNT"
    echo "Mandatory=$MANDATORY_QUESTION_COUNT, ArrayAnswers=$ANSWER_COUNT"
else
    echo "No PHQ-9 survey found in database"
fi

# Sanitize for JSON
SURVEY_TITLE_SAFE=$(echo "$SURVEY_TITLE" | sed 's/"/\\"/g' | tr -d '\n\r')

cat > /tmp/phq9_result.json << EOF
{
    "initial_survey_count": $INITIAL_COUNT,
    "current_survey_count": $CURRENT_SURVEY_COUNT,
    "survey_found": $SURVEY_FOUND,
    "survey_id": "$SID",
    "survey_title": "$SURVEY_TITLE_SAFE",
    "survey_active": "$SURVEY_ACTIVE",
    "survey_anonymized": "$SURVEY_ANONYMIZED",
    "group_count": $GROUP_COUNT,
    "total_question_count": $TOTAL_QUESTION_COUNT,
    "array_question_count": $ARRAY_QUESTION_COUNT,
    "array_subquestion_count": $ARRAY_SUBQUESTION_COUNT,
    "mandatory_question_count": $MANDATORY_QUESTION_COUNT,
    "array_answer_option_count": $ANSWER_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
cat /tmp/phq9_result.json
echo ""
echo "=== Export Complete ==="
