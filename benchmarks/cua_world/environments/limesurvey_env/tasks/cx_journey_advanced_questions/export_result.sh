#!/bin/bash
echo "=== Exporting Customer Experience Survey Result ==="

source /workspace/scripts/task_utils.sh

# Helper to execute SQL
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Find the survey ID based on title
# We look for the most recently created one matching the pattern
echo "Searching for survey..."
SURVEY_INFO=$(limesurvey_query "
SELECT s.sid, sl.surveyls_title, sl.surveyls_welcometext, sl.surveyls_endtext, s.active, s.datecreated
FROM lime_surveys s
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id
WHERE LOWER(sl.surveyls_title) LIKE '%customer experience journey%'
ORDER BY s.datecreated DESC LIMIT 1
")

FOUND="false"
SID=""
TITLE=""
WELCOME=""
ENDTEXT=""
ACTIVE=""
DATECREATED=""

if [ -n "$SURVEY_INFO" ]; then
    FOUND="true"
    # Parse tab-separated values. 
    # Warning: Text fields might contain tabs or newlines, so we handle carefully or accept simple parsing for verification
    SID=$(echo "$SURVEY_INFO" | awk -F'\t' '{print $1}')
    TITLE=$(echo "$SURVEY_INFO" | awk -F'\t' '{print $2}')
    # For long text fields, it's safer to fetch them individually to avoid awk splitting issues
    WELCOME=$(limesurvey_query "SELECT surveyls_welcometext FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
    ENDTEXT=$(limesurvey_query "SELECT surveyls_endtext FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
    ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID")
    DATECREATED=$(limesurvey_query "SELECT datecreated FROM lime_surveys WHERE sid=$SID")
fi

GROUPS_COUNT=0
QUESTIONS_JSON="[]"

if [ "$FOUND" == "true" ]; then
    # Get Group Count
    GROUPS_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID")
    
    # Get Questions Details
    # We construct a JSON array of questions manually using a loop
    # Get QIDs of top-level questions
    QIDS=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND parent_qid=0 ORDER BY qid ASC")
    
    QUESTIONS_LIST=""
    for QID in $QIDS; do
        # Basic Info
        Q_TYPE=$(limesurvey_query "SELECT type FROM lime_questions WHERE qid=$QID")
        Q_TITLE=$(limesurvey_query "SELECT title FROM lime_questions WHERE qid=$QID")
        Q_TEXT=$(limesurvey_query "SELECT question FROM lime_question_l10ns WHERE qid=$QID")
        
        # Count subquestions (for Array, Ranking, Multiple Choice)
        SUB_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE parent_qid=$QID")
        
        # Check attributes (for Numerical min/max)
        MIN_VAL=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute IN ('min_num_value_n', 'minimum_value') LIMIT 1")
        MAX_VAL=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute IN ('max_num_value_n', 'maximum_value') LIMIT 1")
        
        # Sanitize text
        Q_TEXT_SAFE=$(echo "$Q_TEXT" | sed 's/"/\\"/g' | tr -d '\n\r')
        Q_TITLE_SAFE=$(echo "$Q_TITLE" | sed 's/"/\\"/g' | tr -d '\n\r')
        
        ITEM_JSON="{\"qid\": $QID, \"type\": \"$Q_TYPE\", \"title\": \"$Q_TITLE_SAFE\", \"text\": \"$Q_TEXT_SAFE\", \"sub_count\": ${SUB_COUNT:-0}, \"min_val\": \"${MIN_VAL:-}\", \"max_val\": \"${MAX_VAL:-}\"}"
        
        if [ -z "$QUESTIONS_LIST" ]; then
            QUESTIONS_LIST="$ITEM_JSON"
        else
            QUESTIONS_LIST="$QUESTIONS_LIST, $ITEM_JSON"
        fi
    done
    QUESTIONS_JSON="[$QUESTIONS_LIST]"
fi

# Sanitize strings for final JSON
TITLE_SAFE=$(echo "$TITLE" | sed 's/"/\\"/g' | tr -d '\n\r')
WELCOME_SAFE=$(echo "$WELCOME" | sed 's/"/\\"/g' | tr -d '\n\r')
ENDTEXT_SAFE=$(echo "$ENDTEXT" | sed 's/"/\\"/g' | tr -d '\n\r')
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Construct Final JSON
cat > /tmp/cx_journey_result.json << EOF
{
    "found": $FOUND,
    "sid": "${SID:-0}",
    "title": "$TITLE_SAFE",
    "welcome": "$WELCOME_SAFE",
    "endtext": "$ENDTEXT_SAFE",
    "active": "$ACTIVE",
    "date_created": "$DATECREATED",
    "task_start_time": $TASK_START,
    "groups_count": ${GROUPS_COUNT:-0},
    "questions": $QUESTIONS_JSON
}
EOF

echo "Export complete. Result saved to /tmp/cx_journey_result.json"
cat /tmp/cx_journey_result.json