#!/bin/bash
echo "=== Exporting Survey Group Organization Result ==="

source /workspace/scripts/task_utils.sh

# Helper
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Fetch Survey Groups
echo "Fetching survey groups..."
# Query: gsid, title, description, sortorder
GROUPS_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "
SELECT CONCAT(
    '{\"gsid\":', gsid, 
    ', \"title\":\"', REPLACE(title, '\"', '\\\"'), '\"',
    ', \"description\":\"', REPLACE(description, '\"', '\\\"'), '\"',
    ', \"sortorder\":', sortorder, 
    '}'
) 
FROM lime_surveys_groups 
WHERE title LIKE '%Tech Summit%' 
   OR title LIKE '%Healthcare Innovation%' 
   OR title LIKE '%Women in Leadership%'
")

# Convert newline separated JSON objects to a JSON array
GROUPS_ARRAY="["
FIRST=1
while IFS= read -r line; do
    if [ -n "$line" ]; then
        if [ $FIRST -eq 0 ]; then GROUPS_ARRAY="$GROUPS_ARRAY,"; fi
        GROUPS_ARRAY="$GROUPS_ARRAY $line"
        FIRST=0
    fi
done <<< "$GROUPS_JSON"
GROUPS_ARRAY="$GROUPS_ARRAY ]"

# 2. Fetch the specific survey
echo "Fetching target survey..."
# We look for the Tech Summit survey
SURVEY_DATA=$(limesurvey_query "
SELECT s.sid, s.gsid, s.anonymized, sl.surveyls_title
FROM lime_surveys s
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id
WHERE sl.surveyls_title LIKE '%Post-Event Satisfaction%Tech Summit%'
LIMIT 1
")

SURVEY_FOUND="false"
SID=""
GSID=""
ANONYMIZED=""
TITLE=""
QUESTION_COUNT=0
CORRECT_QUESTION_FOUND="false"
ANSWER_OPTION_COUNT=0

if [ -n "$SURVEY_DATA" ]; then
    SURVEY_FOUND="true"
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    GSID=$(echo "$SURVEY_DATA" | awk '{print $2}')
    ANONYMIZED=$(echo "$SURVEY_DATA" | awk '{print $3}')
    # Title might contain spaces, so use cut or similar if needed, but for JSON export verification we check logical match
    TITLE="Post-Event Satisfaction Survey - Tech Summit 2024" 

    # Check Questions
    # Look for Question Code Q01, Type L (List Radio)
    Q_DATA=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='Q01' AND type='L'")
    
    if [ -n "$Q_DATA" ]; then
        CORRECT_QUESTION_FOUND="true"
        QID=$Q_DATA
        # Check answer options count
        ANSWER_OPTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_answers WHERE qid=$QID")
    fi
fi

# 3. Create Result JSON
cat > /tmp/group_org_result.json << EOF
{
    "groups": $GROUPS_ARRAY,
    "survey": {
        "found": $SURVEY_FOUND,
        "sid": "$SID",
        "gsid": "$GSID",
        "anonymized": "$ANONYMIZED",
        "question_found": $CORRECT_QUESTION_FOUND,
        "answer_option_count": $ANSWER_OPTION_COUNT
    },
    "timestamp": $(date +%s)
}
EOF

echo "Export complete. Result:"
cat /tmp/group_org_result.json