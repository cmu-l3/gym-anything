#!/bin/bash
echo "=== Exporting Survey Copy Adaptation Result ==="

source /workspace/scripts/task_utils.sh

# Record end state
take_screenshot /tmp/task_final.png

# Get Source SID from setup
SOURCE_SID=$(cat /tmp/source_sid.txt 2>/dev/null || echo "0")

# 1. Verify Original Survey Still Exists (Gate Check)
ORIGINAL_EXISTS=$(limesurvey_query "SELECT count(*) FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SOURCE_SID AND surveyls_title LIKE '%Annual Tech Conference 2024%'")
echo "Original survey preserved count: $ORIGINAL_EXISTS"

# 2. Find New Survey by Title
# We look for the exact expected title
TARGET_TITLE="Healthcare Innovation Summit 2025 Feedback"
NEW_SURVEY_DATA=$(limesurvey_query "SELECT s.sid, sl.surveyls_title, sl.surveyls_description, sl.surveyls_welcometext, s.expires, s.active 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
WHERE sl.surveyls_title LIKE '%Healthcare Innovation Summit 2025 Feedback%' 
AND s.sid != $SOURCE_SID 
LIMIT 1")

# Initialize variables
NEW_SID=""
TITLE_FOUND=""
DESC_FOUND=""
WELCOME_FOUND=""
EXPIRES_FOUND=""
ACTIVE_FOUND=""
NEW_GROUP_FOUND="false"
NEW_QUESTION_FOUND="false"
QUESTION_TEXT_FOUND=""

if [ -n "$NEW_SURVEY_DATA" ]; then
    # Parse tab-separated result
    NEW_SID=$(echo "$NEW_SURVEY_DATA" | cut -f1)
    TITLE_FOUND=$(echo "$NEW_SURVEY_DATA" | cut -f2)
    DESC_FOUND=$(echo "$NEW_SURVEY_DATA" | cut -f3)
    WELCOME_FOUND=$(echo "$NEW_SURVEY_DATA" | cut -f4)
    EXPIRES_FOUND=$(echo "$NEW_SURVEY_DATA" | cut -f5)
    ACTIVE_FOUND=$(echo "$NEW_SURVEY_DATA" | cut -f6)

    echo "Found new survey SID: $NEW_SID"

    # 3. Check for New Question Group "Clinical Innovation Track"
    GROUP_CHECK=$(limesurvey_query "SELECT count(*) FROM lime_groups_languagesettings WHERE surveyls_survey_id=$NEW_SID AND group_name LIKE '%Clinical Innovation Track%'")
    if [ "$GROUP_CHECK" -gt 0 ]; then
        NEW_GROUP_FOUND="true"
    fi

    # 4. Check for New Question "ClinicalRelevance"
    # Need to find the QID first to check text
    QUESTION_DATA=$(limesurvey_query "SELECT q.qid, ql.question FROM lime_questions q JOIN lime_question_l10ns ql ON q.qid = ql.qid WHERE q.sid=$NEW_SID AND q.title='ClinicalRelevance'")
    
    if [ -n "$QUESTION_DATA" ]; then
        NEW_QUESTION_FOUND="true"
        QUESTION_TEXT_FOUND=$(echo "$QUESTION_DATA" | cut -f2)
    fi
else
    echo "Target survey not found by title."
fi

# Prepare JSON Result
cat > /tmp/task_result.json << EOF
{
    "original_preserved": $ORIGINAL_EXISTS,
    "new_survey_found": $([ -n "$NEW_SID" ] && echo "true" || echo "false"),
    "new_sid": "$NEW_SID",
    "title": $(echo "$TITLE_FOUND" | jq -R .),
    "description": $(echo "$DESC_FOUND" | jq -R .),
    "welcome_text": $(echo "$WELCOME_FOUND" | jq -R .),
    "expiration": "$EXPIRES_FOUND",
    "active": "$ACTIVE_FOUND",
    "group_added": $NEW_GROUP_FOUND,
    "question_added": $NEW_QUESTION_FOUND,
    "question_text": $(echo "$QUESTION_TEXT_FOUND" | jq -R .),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="