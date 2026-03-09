#!/bin/bash
echo "=== Exporting CRM Integration Result ==="

source /workspace/scripts/task_utils.sh

if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Find the survey SID
echo "Finding survey..."
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Zendesk Support Feedback 2025%' LIMIT 1")

SURVEY_FOUND="false"
IS_ACTIVE="false"
QUESTIONS_JSON="[]"
ATTRIBUTES_JSON="[]"
URL_PARAMS_JSON="[]"
GROUPS_JSON="[]"

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey SID: $SID"

    # Check active status
    ACTIVE_STATUS=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID")
    if [ "$ACTIVE_STATUS" == "Y" ]; then
        IS_ACTIVE="true"
    fi

    # Get Groups
    GROUPS_JSON=$(limesurvey_query "SELECT gid, group_name FROM lime_groups WHERE sid=$SID" | \
        python3 -c "import sys, json; print(json.dumps([{'gid': line.split('\t')[0], 'name': line.split('\t')[1].strip()} for line in sys.stdin if '\t' in line]))")

    # Get Questions (QID, Title/Code, Text, Type)
    # Using python to format as JSON safely
    QUESTIONS_JSON=$(limesurvey_query "SELECT q.qid, q.title, l.question, q.type FROM lime_questions q JOIN lime_question_l10ns l ON q.qid=l.qid WHERE q.sid=$SID AND q.language='en'" | \
        python3 -c "import sys, json; print(json.dumps([{'qid': line.split('\t')[0], 'code': line.split('\t')[1], 'text': line.split('\t')[2], 'type': line.split('\t')[3].strip()} for line in sys.stdin if '\t' in line]))")

    # Get Hidden Attributes
    # We need to know which QIDs are hidden.
    # Attribute 'hidden' value '1' in lime_question_attributes
    ATTRIBUTES_JSON=$(limesurvey_query "SELECT qid, attribute, value FROM lime_question_attributes WHERE attribute='hidden'" | \
        python3 -c "import sys, json; print(json.dumps([{'qid': line.split('\t')[0], 'attribute': line.split('\t')[1], 'value': line.split('\t')[2].strip()} for line in sys.stdin if '\t' in line]))")

    # Get URL Parameters
    URL_PARAMS_JSON=$(limesurvey_query "SELECT parameter, targetqid, title FROM lime_survey_url_parameters WHERE sid=$SID" | \
        python3 -c "import sys, json; print(json.dumps([{'parameter': line.split('\t')[0], 'targetqid': line.split('\t')[1], 'title': line.split('\t')[2].strip() if len(line.split('\t'))>2 else ''} for line in sys.stdin if '\t' in line]))")

else
    echo "Survey not found."
fi

# Build final JSON
cat > /tmp/task_result.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "is_active": $IS_ACTIVE,
    "groups": $GROUPS_JSON,
    "questions": $QUESTIONS_JSON,
    "attributes": $ATTRIBUTES_JSON,
    "url_params": $URL_PARAMS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json