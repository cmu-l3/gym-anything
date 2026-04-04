#!/bin/bash
echo "=== Exporting Conditional Event Feedback Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the Survey ID based on title
# We look for 'TechSummit' in the title
SURVEY_DATA=$(limesurvey_query "SELECT s.sid, sl.surveyls_title, s.active, s.datecreated 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
WHERE sl.surveyls_title LIKE '%TechSummit%' 
ORDER BY s.datecreated DESC LIMIT 1" 2>/dev/null)

SURVEY_FOUND="false"
SID=""
TITLE=""
ACTIVE="N"
CREATED_DATE=""
GROUP_COUNT=0
QUESTION_COUNT=0
GROUPS_WITH_RELEVANCE=0
QUESTIONS_WITH_RELEVANCE=0
ATTENDANCE_Q_TYPE=""
ATTENDANCE_OPTIONS=0

if [ -n "$SURVEY_DATA" ]; then
    SURVEY_FOUND="true"
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    # Extract title handling spaces (everything between first and last 2 columns)
    TITLE=$(echo "$SURVEY_DATA" | awk '{$1=""; $(NF-1)=""; $NF=""; print}' | sed 's/^ *//;s/ *$//')
    ACTIVE=$(echo "$SURVEY_DATA" | awk '{print $(NF-1)}') # Active is actually 3rd column in query? No, awk splits by space.
    # Let's re-parse safely. 
    # Query: sid [tab] title [tab] active [tab] datecreated
    # Since we use mysql -N -e, output is tab separated usually, but sometimes space if not configured.
    # Let's use specific queries for safety once we have SID.
    
    TITLE=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID" 2>/dev/null)
    ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID" 2>/dev/null)
    CREATED_DATE=$(limesurvey_query "SELECT datecreated FROM lime_surveys WHERE sid=$SID" 2>/dev/null)
    
    # 2. Count Groups
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID" 2>/dev/null || echo "0")
    
    # 3. Count Questions (Parent questions only)
    QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0" 2>/dev/null || echo "0")
    
    # 4. Check Group Relevance (Branching)
    # Relevance '1' is default (always show). Empty or NULL also effectively means show (depending on version), but explicit logic usually looks like "AttendType == 'A1'".
    # We count groups where grelevance is NOT 1 and has length > 1
    GROUPS_WITH_RELEVANCE=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID AND grelevance IS NOT NULL AND grelevance != '1' AND LENGTH(grelevance) > 3" 2>/dev/null || echo "0")
    
    # 5. Check Question Relevance (Branching)
    QUESTIONS_WITH_RELEVANCE=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0 AND relevance IS NOT NULL AND relevance != '1' AND LENGTH(relevance) > 3" 2>/dev/null || echo "0")
    
    # 6. Check Attendance Question Type and Options
    # Look for question code 'AttendType' or similar, type 'L' (List Radio)
    ATTEND_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND (title LIKE '%Attend%' OR title LIKE '%Type%') AND type='L' LIMIT 1" 2>/dev/null)
    
    if [ -n "$ATTEND_QID" ]; then
        ATTENDANCE_Q_TYPE="L"
        ATTENDANCE_OPTIONS=$(limesurvey_query "SELECT COUNT(*) FROM lime_answers WHERE qid=$ATTEND_QID" 2>/dev/null || echo "0")
    fi
fi

# Sanitize strings
TITLE_SAFE=$(echo "$TITLE" | sed 's/"/\\"/g' | tr -d '\n\r')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "title": "$TITLE_SAFE",
    "active": "$ACTIVE",
    "group_count": $GROUP_COUNT,
    "question_count": $QUESTION_COUNT,
    "groups_with_relevance": $GROUPS_WITH_RELEVANCE,
    "questions_with_relevance": $QUESTIONS_WITH_RELEVANCE,
    "attendance_q_type": "$ATTENDANCE_Q_TYPE",
    "attendance_options": $ATTENDANCE_OPTIONS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="