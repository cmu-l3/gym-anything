#!/bin/bash
echo "=== Exporting HR Roster Import Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Identify the Survey ID (SID)
# Look for survey with "Employee Engagement" in title
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%employee%engagement%' ORDER BY s.datecreated DESC LIMIT 1")

SURVEY_FOUND="false"
PARTICIPANT_COUNT=0
MAPPING_TEST_EMAIL="s.connor@cyberdyne.com"
ATTR1_VALUE=""
ATTR2_VALUE=""
ATTR3_VALUE=""
PIPING_SYNTAX_FOUND="false"
QUESTION_TEXT=""

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey ID: $SID"

    # 3. Check Participant Table (lime_tokens_SID)
    # Verify table exists first
    TABLE_EXISTS=$(limesurvey_query "SHOW TABLES LIKE 'lime_tokens_$SID'")
    
    if [ -n "$TABLE_EXISTS" ]; then
        # Get count
        PARTICIPANT_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_tokens_$SID")
        
        # Check specific mapping for test user
        # We grab attribute_1, attribute_2, attribute_3 for Sarah Connor
        ROW_DATA=$(limesurvey_query "SELECT attribute_1, attribute_2, attribute_3 FROM lime_tokens_$SID WHERE email='$MAPPING_TEST_EMAIL'")
        
        if [ -n "$ROW_DATA" ]; then
            ATTR1_VALUE=$(echo "$ROW_DATA" | cut -f1)
            ATTR2_VALUE=$(echo "$ROW_DATA" | cut -f2)
            ATTR3_VALUE=$(echo "$ROW_DATA" | cut -f3)
        fi
    fi

    # 4. Check Question Piping
    # Look for question text containing token attribute syntax
    # We check lime_question_l10ns for the question text
    QUESTION_TEXT=$(limesurvey_query "SELECT question FROM lime_question_l10ns WHERE question LIKE '%TOKEN:ATTRIBUTE_1%' AND qid IN (SELECT qid FROM lime_questions WHERE sid=$SID) LIMIT 1")
    
    if [ -n "$QUESTION_TEXT" ]; then
        PIPING_SYNTAX_FOUND="true"
    fi
fi

# 5. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "participant_count": ${PARTICIPANT_COUNT:-0},
    "test_user_mapping": {
        "email": "$MAPPING_TEST_EMAIL",
        "attr1_val": "$ATTR1_VALUE",
        "attr2_val": "$ATTR2_VALUE",
        "attr3_val": "$ATTR3_VALUE"
    },
    "piping_syntax_found": $PIPING_SYNTAX_FOUND,
    "question_text_sample": "$(echo "$QUESTION_TEXT" | sed 's/"/\\"/g' | head -c 200)",
    "timestamp": $(date +%s)
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json