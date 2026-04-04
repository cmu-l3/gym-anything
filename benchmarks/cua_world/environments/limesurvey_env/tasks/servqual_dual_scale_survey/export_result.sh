#!/bin/bash
echo "=== Exporting SERVQUAL Survey Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Identify the target survey
# We look for the most recently created survey that matches the title keywords
echo "Searching for survey..."
SURVEY_QUERY="SELECT s.sid, sl.surveyls_title, s.active, s.anonymized 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
WHERE (LOWER(sl.surveyls_title) LIKE '%servqual%' OR LOWER(sl.surveyls_title) LIKE '%service quality%')
ORDER BY s.datecreated DESC LIMIT 1"

SURVEY_DATA=$(limesurvey_query "$SURVEY_QUERY")

FOUND="false"
SID=""
TITLE=""
ACTIVE="N"
ANONYMIZED="N"
GROUP_COUNT=0
DUAL_SCALE_FOUND="false"
DUAL_SCALE_QID=""
SUBQUESTION_COUNT=0
SCALE_COUNT=0
FREE_TEXT_FOUND="false"

if [ -n "$SURVEY_DATA" ]; then
    FOUND="true"
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    # Extract title (everything between first and second-to-last column)
    # This is a bit hacky with awk, so we'll just fetch title separately to be safe
    TITLE=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID LIMIT 1")
    ACTIVE=$(echo "$SURVEY_DATA" | awk '{print $(NF-1)}')
    ANONYMIZED=$(echo "$SURVEY_DATA" | awk '{print $NF}')
    
    echo "Found Survey SID: $SID, Title: $TITLE"

    # 3. Check Question Groups
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID")
    
    # 4. Check for Array (Dual Scale) Question (Type '1')
    # parent_qid=0 ensures it's the main question, not a subquestion
    DUAL_SCALE_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND type='1' AND parent_qid=0 LIMIT 1")
    
    if [ -n "$DUAL_SCALE_QID" ]; then
        DUAL_SCALE_FOUND="true"
        echo "Found Dual Scale Question QID: $DUAL_SCALE_QID"
        
        # 5. Count Sub-questions
        # Sub-questions have parent_qid = DUAL_SCALE_QID
        # Note: In dual scale, sometimes scale_id might be used, but usually just parent_qid relates them
        SUBQUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE parent_qid=$DUAL_SCALE_QID")
        
        # 6. Check for Dual Scales (Answer Options)
        # We check the lime_answers table. Valid dual scale setup must have answers for scale_id 0 and scale_id 1
        SCALE_COUNT=$(limesurvey_query "SELECT COUNT(DISTINCT scale_id) FROM lime_answers WHERE qid=$DUAL_SCALE_QID")
    fi
    
    # 7. Check for Long Free Text (Type 'T')
    FREE_TEXT_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND type='T' AND parent_qid=0 LIMIT 1")
    if [ -n "$FREE_TEXT_QID" ]; then
        FREE_TEXT_FOUND="true"
    else
         # Fallback: check for Huge Free Text ('U') or Short Text ('S') just in case
         FREE_TEXT_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND type IN ('U', 'S') AND parent_qid=0 LIMIT 1")
         if [ -n "$FREE_TEXT_QID" ]; then
             FREE_TEXT_FOUND="true_alt_type"
         fi
    fi
fi

# 8. Escape strings for JSON
TITLE_JSON=$(echo "$TITLE" | sed 's/"/\\"/g')

# 9. Create JSON Result
cat > /tmp/servqual_result.json << EOF
{
    "survey_found": $FOUND,
    "sid": "$SID",
    "title": "$TITLE_JSON",
    "active": "$ACTIVE",
    "anonymized": "$ANONYMIZED",
    "group_count": ${GROUP_COUNT:-0},
    "dual_scale_found": $DUAL_SCALE_FOUND,
    "subquestion_count": ${SUBQUESTION_COUNT:-0},
    "scale_count": ${SCALE_COUNT:-0},
    "free_text_found": "$FREE_TEXT_FOUND",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. Result:"
cat /tmp/servqual_result.json