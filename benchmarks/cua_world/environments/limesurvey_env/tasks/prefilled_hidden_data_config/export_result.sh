#!/bin/bash
echo "=== Exporting Prefilled Hidden Data Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. FIND THE SURVEY
# ------------------
SURVEY_DATA=$(limesurvey_query "SELECT s.sid, sl.surveyls_title 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id 
WHERE sl.surveyls_title LIKE '%Employee Engagement Pulse%' 
ORDER BY s.datecreated DESC LIMIT 1")

SID=""
TITLE=""
TOKENS_TABLE_EXISTS="false"
ATTRIBUTES_EXIST="false"
PARTICIPANT_FOUND="false"
QUESTIONS_FOUND="false"
HIDDEN_CONFIG_CORRECT="false"
DEPT_DEFAULT=""
ROLE_DEFAULT=""

if [ -n "$SURVEY_DATA" ]; then
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    TITLE=$(echo "$SURVEY_DATA" | cut -f2-)
    echo "Found Survey: SID=$SID, Title=$TITLE"

    # 2. CHECK TOKEN TABLE AND ATTRIBUTES
    # -----------------------------------
    TOKEN_TABLE="lime_tokens_$SID"
    TABLE_CHECK=$(limesurvey_query "SHOW TABLES LIKE '$TOKEN_TABLE'")
    
    if [ -n "$TABLE_CHECK" ]; then
        TOKENS_TABLE_EXISTS="true"
        
        # Check columns for attributes
        COLUMNS=$(limesurvey_query "SHOW COLUMNS FROM $TOKEN_TABLE")
        if echo "$COLUMNS" | grep -q "attribute_1" && echo "$COLUMNS" | grep -q "attribute_2"; then
            ATTRIBUTES_EXIST="true"
        fi
        
        # Check Participant
        PARTICIPANT=$(limesurvey_query "SELECT firstname, lastname, email, attribute_1, attribute_2 FROM $TOKEN_TABLE WHERE email LIKE '%elena.rossi%' LIMIT 1")
        if [ -n "$PARTICIPANT" ]; then
            PARTICIPANT_FOUND="true"
            # Extract attributes for logs
            P_ATTR1=$(echo "$PARTICIPANT" | awk '{print $4}')
            P_ATTR2=$(echo "$PARTICIPANT" | awk '{print $5}')
            echo "Participant found with attrs: $P_ATTR1, $P_ATTR2"
        fi
    fi

    # 3. CHECK QUESTIONS CONFIGURATION
    # --------------------------------
    # Get questions sys_dept and sys_role
    # We check:
    # - Existence
    # - Hidden attribute (table lime_question_attributes, attribute='hidden', value='1')
    # - Default value (table lime_questions, column 'default' OR 'question' text sometimes?)
    #   Note: In newer LS, 'default' column in lime_questions holds the default value expression.
    
    Q_DEPT_DATA=$(limesurvey_query "SELECT qid, title, \`default\` FROM lime_questions WHERE sid=$SID AND title='sys_dept'")
    Q_ROLE_DATA=$(limesurvey_query "SELECT qid, title, \`default\` FROM lime_questions WHERE sid=$SID AND title='sys_role'")
    
    if [ -n "$Q_DEPT_DATA" ] && [ -n "$Q_ROLE_DATA" ]; then
        QUESTIONS_FOUND="true"
        
        QID_DEPT=$(echo "$Q_DEPT_DATA" | awk '{print $1}')
        DEPT_DEFAULT=$(echo "$Q_DEPT_DATA" | cut -f3-) # The rest of the line is the default val
        
        QID_ROLE=$(echo "$Q_ROLE_DATA" | awk '{print $1}')
        ROLE_DEFAULT=$(echo "$Q_ROLE_DATA" | cut -f3-)

        # Check Hidden Attribute
        HIDDEN_DEPT=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID_DEPT AND attribute='hidden'")
        HIDDEN_ROLE=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID_ROLE AND attribute='hidden'")
        
        if [ "$HIDDEN_DEPT" == "1" ] && [ "$HIDDEN_ROLE" == "1" ]; then
            HIDDEN_CONFIG_CORRECT="true"
        fi
    fi
fi

# Create JSON Result
cat > /tmp/config_result.json << EOF
{
    "survey_found": $([ -n "$SID" ] && echo "true" || echo "false"),
    "survey_sid": "$SID",
    "survey_title": "$TITLE",
    "tokens_table_exists": $TOKENS_TABLE_EXISTS,
    "attributes_created": $ATTRIBUTES_EXIST,
    "participant_found": $PARTICIPANT_FOUND,
    "questions_found": $QUESTIONS_FOUND,
    "hidden_config_correct": $HIDDEN_CONFIG_CORRECT,
    "dept_default_value": "$DEPT_DEFAULT",
    "role_default_value": "$ROLE_DEFAULT",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to safe location
export_json_result "$(cat /tmp/config_result.json)" "/tmp/task_result.json"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="