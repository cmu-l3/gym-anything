#!/bin/bash
echo "=== Exporting Feature Ranking Survey Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Identify the target survey
# We look for the most recently created survey that matches the title keywords
TARGET_SID=$(limesurvey_query "
    SELECT s.sid 
    FROM lime_surveys s 
    JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
    WHERE (LOWER(sl.surveyls_title) LIKE '%smart home%' OR LOWER(sl.surveyls_title) LIKE '%feature prioritization%')
    ORDER BY s.datecreated DESC 
    LIMIT 1
" 2>/dev/null)

echo "Found Target SID: $TARGET_SID"

# Initialize JSON fields
SURVEY_EXISTS="false"
SURVEY_TITLE=""
SURVEY_FORMAT=""
SURVEY_ACTIVE="N"
GROUP_COUNT=0
QUESTIONS_JSON="[]"
SUBQUESTIONS_JSON="[]"

if [ -n "$TARGET_SID" ]; then
    SURVEY_EXISTS="true"
    
    # Get Survey Info
    SURVEY_INFO=$(limesurvey_query "
        SELECT sl.surveyls_title, s.format, s.active
        FROM lime_surveys s 
        JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
        WHERE s.sid = $TARGET_SID
    ")
    SURVEY_TITLE=$(echo "$SURVEY_INFO" | cut -f1)
    SURVEY_FORMAT=$(echo "$SURVEY_INFO" | cut -f2)
    SURVEY_ACTIVE=$(echo "$SURVEY_INFO" | cut -f3)
    
    # Get Group Count
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid = $TARGET_SID")
    
    # Get Questions (Main questions only, parent_qid=0)
    # Fields: qid, type, mandatory, title (code), question (text)
    # Using python to format SQL output as JSON to handle quotes properly
    QUESTIONS_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "
        SELECT 
            q.qid, q.type, q.mandatory, q.title, REPLACE(ql.question, '\"', '\\\"')
        FROM lime_questions q
        JOIN lime_question_l10ns ql ON q.qid = ql.qid
        WHERE q.sid = $TARGET_SID AND q.parent_qid = 0
    " | python3 -c '
import sys, json
questions = []
for line in sys.stdin:
    parts = line.strip().split("\t")
    if len(parts) >= 4:
        questions.append({
            "qid": parts[0],
            "type": parts[1],
            "mandatory": parts[2],
            "code": parts[3],
            "text": parts[4] if len(parts) > 4 else ""
        })
print(json.dumps(questions))
    ')

    # Get Subquestions count for each question
    # We specifically need to check the Ranking question subquestions
    SUBQUESTIONS_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "
        SELECT parent_qid, COUNT(*) 
        FROM lime_questions 
        WHERE sid = $TARGET_SID AND parent_qid != 0 
        GROUP BY parent_qid
    " | python3 -c '
import sys, json
counts = {}
for line in sys.stdin:
    parts = line.strip().split("\t")
    if len(parts) == 2:
        counts[parts[0]] = int(parts[1])
print(json.dumps(counts))
    ')
fi

# 3. Create Result JSON
cat > /tmp/task_result.json <<EOF
{
    "survey_exists": $SURVEY_EXISTS,
    "survey_sid": "$TARGET_SID",
    "survey_title": "$(echo $SURVEY_TITLE | sed 's/"/\\"/g')",
    "survey_format": "$SURVEY_FORMAT",
    "survey_active": "$SURVEY_ACTIVE",
    "group_count": ${GROUP_COUNT:-0},
    "questions": $QUESTIONS_JSON,
    "subquestion_counts": $SUBQUESTIONS_JSON,
    "timestamp": "$(date +%s)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="