#!/bin/bash
echo "=== Exporting Clinical Safety Protocol Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

SID=$(cat /tmp/task_sid.txt 2>/dev/null)
if [ -z "$SID" ]; then
    # Fallback search
    SID=$(limesurvey_query "SELECT sid FROM lime_surveys_languagesettings WHERE surveyls_title='Depression Screening - Fall 2024' LIMIT 1")
fi

echo "Checking Survey ID: $SID"

# 1. Check Notification Settings (Expression Manager usage)
# We check 'surveyls_email_alert_to' (Detailed admin notification)
EMAIL_ALERT_TO=$(limesurvey_query "SELECT surveyls_email_alert_to FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'")

# 2. Check for Intervention Question
# We look for a question of type 'X' (Text Display) in this survey
# We get the one that resembles our request
INTERVENTION_Q_DATA=$(limesurvey_query "SELECT q.qid, q.title, q.type, q.relevance, ql.question 
    FROM lime_questions q 
    JOIN lime_question_l10ns ql ON q.qid = ql.qid 
    WHERE q.sid=$SID AND q.type='X' 
    LIMIT 1")

QID=""
TITLE=""
TYPE=""
RELEVANCE=""
TEXT=""

if [ -n "$INTERVENTION_Q_DATA" ]; then
    # Parse tab separated values
    QID=$(echo "$INTERVENTION_Q_DATA" | cut -f1)
    TITLE=$(echo "$INTERVENTION_Q_DATA" | cut -f2)
    TYPE=$(echo "$INTERVENTION_Q_DATA" | cut -f3)
    RELEVANCE=$(echo "$INTERVENTION_Q_DATA" | cut -f4)
    TEXT=$(echo "$INTERVENTION_Q_DATA" | cut -f5-)
fi

# Sanitize for JSON
EMAIL_ALERT_SAFE=$(echo "$EMAIL_ALERT_TO" | sed 's/"/\\"/g' | tr -d '\n\r')
TEXT_SAFE=$(echo "$TEXT" | sed 's/"/\\"/g' | tr -d '\n\r')
RELEVANCE_SAFE=$(echo "$RELEVANCE" | sed 's/"/\\"/g' | tr -d '\n\r')

cat > /tmp/result.json << EOF
{
    "sid": "$SID",
    "email_alert_to": "$EMAIL_ALERT_SAFE",
    "intervention_question": {
        "found": $(if [ -n "$QID" ]; then echo "true"; else echo "false"; fi),
        "qid": "$QID",
        "title": "$TITLE",
        "type": "$TYPE",
        "relevance": "$RELEVANCE_SAFE",
        "text": "$TEXT_SAFE"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to safe location
mv /tmp/result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

cat /tmp/task_result.json
echo "=== Export Complete ==="