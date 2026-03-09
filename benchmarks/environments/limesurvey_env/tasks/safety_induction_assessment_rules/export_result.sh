#!/bin/bash
echo "=== Exporting Safety Induction Assessment Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Identify the Survey SID
# We look for the specific title
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Site Safety Induction Exam 2024%' LIMIT 1" 2>/dev/null || echo "")

RESULT_JSON="{}"

if [ -z "$SID" ]; then
    echo "Survey not found."
    # Create empty result
    cat > /tmp/task_result.json << EOF
{
    "survey_found": false,
    "timestamp": "$(date -Iseconds)"
}
EOF
else
    echo "Found Survey SID: $SID"

    # 2. Check Survey Settings (Assessments enabled, Active)
    ASSESSMENTS_ENABLED=$(limesurvey_query "SELECT assessments FROM lime_surveys WHERE sid=$SID" 2>/dev/null || echo "N")
    ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID" 2>/dev/null || echo "N")

    # 3. Check Assessment Rules
    # Get all rules for this SID
    RULES_JSON=$(limesurvey_query "SELECT min, max, message FROM lime_assessments WHERE sid=$SID" 2>/dev/null | \
        while read -r min max msg; do
            # Escape quotes in message
            clean_msg=$(echo "$msg" | sed 's/"/\\"/g')
            echo "{\"min\": \"$min\", \"max\": \"$max\", \"message\": \"$clean_msg\"},"
        done | sed '$ s/,$//') # remove trailing comma

    # 4. Check Question Answers and Values
    # We join answers with questions to see the text and the assigned value
    # We look specifically for the answers we care about
    ANSWERS_JSON=$(limesurvey_query "SELECT q.question, a.answer, a.assessment_value 
        FROM lime_answers a 
        JOIN lime_questions q ON a.qid = q.qid 
        JOIN lime_question_l10ns ql ON q.qid = ql.qid
        WHERE q.sid=$SID AND a.language='en'" 2>/dev/null | \
        while read -r qtext atext val; do
            clean_q=$(echo "$qtext" | sed 's/"/\\"/g')
            clean_a=$(echo "$atext" | sed 's/"/\\"/g')
            echo "{\"question\": \"$clean_q\", \"answer\": \"$clean_a\", \"value\": \"$val\"},"
        done | sed '$ s/,$//')

    # Construct final JSON
    cat > /tmp/task_result.json << EOF
{
    "survey_found": true,
    "sid": "$SID",
    "assessments_enabled": "$ASSESSMENTS_ENABLED",
    "active": "$ACTIVE",
    "rules": [$RULES_JSON],
    "answers": [$ANSWERS_JSON],
    "timestamp": "$(date -Iseconds)"
}
EOF
fi

# Secure the file
chmod 666 /tmp/task_result.json

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="