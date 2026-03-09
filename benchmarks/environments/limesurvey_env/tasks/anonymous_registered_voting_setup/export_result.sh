#!/bin/bash
echo "=== Exporting Anonymous Registered Voting Result ==="

source /workspace/scripts/task_utils.sh

# Helper for SQL
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Find the Survey ID
echo "Finding survey..."
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%2025%employee%benefits%' LIMIT 1")

SURVEY_FOUND="false"
ANONYMIZED="N"
ALLOW_REGISTER="N"
TOKENS_INIT="false"
ATTRIBUTE_FOUND="false"
EMAIL_SUBJ_MATCH="false"
EMAIL_BODY_MATCH="false"
SURVEY_ACTIVE="N"
RAW_SUBJECT=""
RAW_BODY=""

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Survey found: SID=$SID"

    # 2. Check General Settings (Anonymized + Public Registration)
    SETTINGS=$(limesurvey_query "SELECT anonymized, allowregister, active FROM lime_surveys WHERE sid=$SID")
    ANONYMIZED=$(echo "$SETTINGS" | cut -f1)
    ALLOW_REGISTER=$(echo "$SETTINGS" | cut -f2)
    SURVEY_ACTIVE=$(echo "$SETTINGS" | cut -f3)

    # 3. Check Token Table (Initialization)
    TOKEN_TABLE_CHECK=$(limesurvey_query "SHOW TABLES LIKE 'lime_tokens_$SID'")
    if [ -n "$TOKEN_TABLE_CHECK" ]; then
        TOKENS_INIT="true"
        
        # 4. Check Custom Attribute (EmployeeID)
        # In LimeSurvey, creating a custom attribute usually adds 'attribute_1', 'attribute_2', etc. to the token table.
        # The name/description is stored in lime_surveys_languagesettings.surveyls_attributedescriptions (JSON)
        # OR in older versions in a separate table. We check for the column first.
        
        ATTR_COLS=$(limesurvey_query "SELECT count(*) FROM information_schema.columns WHERE table_name = 'lime_tokens_$SID' AND column_name LIKE 'attribute_%'")
        
        # Check descriptions for "EmployeeID"
        ATTR_DESCRIPTIONS=$(limesurvey_query "SELECT surveyls_attributedescriptions FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
        
        if echo "$ATTR_DESCRIPTIONS" | grep -qi "EmployeeID"; then
            ATTRIBUTE_FOUND="true"
        fi
    fi

    # 5. Check Email Templates
    EMAIL_DATA=$(limesurvey_query "SELECT surveyls_email_register_subj, surveyls_email_register FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
    # Use python to parse complex text safely if needed, but grep is okay for simple checks
    RAW_SUBJECT=$(echo "$EMAIL_DATA" | cut -f1)
    RAW_BODY=$(echo "$EMAIL_DATA" | cut -f2)

    if echo "$RAW_SUBJECT" | grep -qi "Your Voting Link"; then
        EMAIL_SUBJ_MATCH="true"
    fi
    
    if echo "$RAW_BODY" | grep -qi "vote is anonymous"; then
        EMAIL_BODY_MATCH="true"
    fi

else
    echo "Survey not found."
fi

# Sanitize strings for JSON
SAFE_SUBJECT=$(echo "$RAW_SUBJECT" | sed 's/"/\\"/g' | tr -d '\n\r')

# Create JSON
cat > /tmp/voting_result.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "anonymized": "$ANONYMIZED",
    "allow_register": "$ALLOW_REGISTER",
    "active": "$SURVEY_ACTIVE",
    "tokens_initialized": $TOKENS_INIT,
    "attribute_found": $ATTRIBUTE_FOUND,
    "email_subject_correct": $EMAIL_SUBJ_MATCH,
    "email_body_correct": $EMAIL_BODY_MATCH,
    "raw_subject": "$SAFE_SUBJECT",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/voting_result.json"
cat /tmp/voting_result.json
echo "=== Export Complete ==="