#!/bin/bash
echo "=== Exporting Sociology Survey Result ==="

source /workspace/scripts/task_utils.sh

# Helper for DB queries
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the survey
# Search for exact title first, then fuzzy match
SURVEY_TITLE="Social Media Usage and Community Belonging Study 2024"
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '$SURVEY_TITLE' ORDER BY surveyls_survey_id DESC LIMIT 1")

# If not found exact, try partial
if [ -z "$SID" ]; then
    SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Social Media Usage%' ORDER BY surveyls_survey_id DESC LIMIT 1")
fi

# If still not found, get the most recently created survey (to give feedback)
if [ -z "$SID" ]; then
    SID=$(limesurvey_query "SELECT sid FROM lime_surveys ORDER BY datecreated DESC LIMIT 1")
fi

echo "Target Survey ID: $SID"

# Initialize JSON fields
FOUND="false"
TITLE=""
DESCRIPTION=""
WELCOME=""
ENDTEXT=""
ANONYMIZED="N"
DATESTAMP="N"
IPADDR="Y"
POLICY_NOTICE="0"
FORMAT=""
SHOW_PROGRESS="N"
ACTIVE="N"
GROUP_COUNT="0"
CONSENT_Q_EXISTS="false"
CREATED_DATE=""

if [ -n "$SID" ]; then
    FOUND="true"
    
    # Get Text Elements
    TITLE=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'")
    DESCRIPTION=$(limesurvey_query "SELECT surveyls_description FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'")
    WELCOME=$(limesurvey_query "SELECT surveyls_welcometext FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'")
    ENDTEXT=$(limesurvey_query "SELECT surveyls_endtext FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'")
    
    # Get Settings
    # Note: LimeSurvey table columns might vary slightly by version, but these are standard
    SETTINGS=$(limesurvey_query "SELECT anonymized, datestamp, ipaddr, showsurveypolicynotice, format, showprogress, active, datecreated FROM lime_surveys WHERE sid=$SID")
    
    # Parse settings (tab separated)
    ANONYMIZED=$(echo "$SETTINGS" | cut -f1)
    DATESTAMP=$(echo "$SETTINGS" | cut -f2)
    IPADDR=$(echo "$SETTINGS" | cut -f3)
    POLICY_NOTICE=$(echo "$SETTINGS" | cut -f4)
    FORMAT=$(echo "$SETTINGS" | cut -f5)
    SHOW_PROGRESS=$(echo "$SETTINGS" | cut -f6)
    ACTIVE=$(echo "$SETTINGS" | cut -f7)
    CREATED_DATE=$(echo "$SETTINGS" | cut -f8)
    
    # Get Structure
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID")
    
    # Check for Consent Question
    # Logic: Look for a mandatory question in the first group (order usually determined by GID or group_order)
    # We check if ANY mandatory question exists in the survey that looks like consent
    CONSENT_Q_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions q JOIN lime_groups g ON q.gid=g.gid WHERE q.sid=$SID AND q.mandatory='Y' AND (g.group_name LIKE '%Consent%' OR q.title LIKE '%Consent%')")
    if [ "$CONSENT_Q_COUNT" -gt 0 ]; then
        CONSENT_Q_EXISTS="true"
    fi
fi

# Sanitize strings for JSON (escape quotes and newlines)
sanitize() {
    echo "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

SAFE_TITLE=$(echo "$TITLE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
# Use python for safer large text block escaping
SAFE_DESC=$(echo "$DESCRIPTION" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
SAFE_WELCOME=$(echo "$WELCOME" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
SAFE_ENDTEXT=$(echo "$ENDTEXT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')

# Create JSON
cat > /tmp/task_result.json << EOF
{
    "found": $FOUND,
    "sid": "$SID",
    "title": $SAFE_TITLE,
    "description": $SAFE_DESC,
    "welcome_text": $SAFE_WELCOME,
    "end_text": $SAFE_ENDTEXT,
    "settings": {
        "anonymized": "$ANONYMIZED",
        "datestamp": "$DATESTAMP",
        "ipaddr": "$IPADDR",
        "policy_notice": "$POLICY_NOTICE",
        "format": "$FORMAT",
        "show_progress": "$SHOW_PROGRESS",
        "active": "$ACTIVE"
    },
    "structure": {
        "group_count": $GROUP_COUNT,
        "consent_question_exists": $CONSENT_Q_EXISTS
    },
    "created_date": "$CREATED_DATE",
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json