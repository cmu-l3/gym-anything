#!/bin/bash
echo "=== Exporting Multilingual Trust Survey Result ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Identify the survey ID (SID)
# We look for a survey created AFTER the task started, or with the correct title
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE ls.surveyls_title LIKE '%Social Trust%' LIMIT 1")

if [ -z "$SID" ]; then
    echo "Survey not found by title, checking newest survey..."
    SID=$(limesurvey_query "SELECT sid FROM lime_surveys ORDER BY datecreated DESC LIMIT 1")
fi

echo "Found SID: $SID"

# Initialize variables
SURVEY_FOUND="false"
TITLE_EN=""
TITLE_ES=""
LANGUAGES=""
ACTIVE="N"
GROUP_COUNT=0
GROUP_ES_COUNT=0
QUESTION_COUNT=0
QUESTION_ES_COUNT=0
ARRAY_SUBQ_COUNT=0
ANSWER_OPTION_ES_COUNT=0

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    
    # Get Titles
    TITLE_EN=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'")
    TITLE_ES=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='es'")
    
    # Get Languages
    LANGUAGES=$(limesurvey_query "SELECT additional_languages FROM lime_surveys WHERE sid=$SID")
    
    # Get Active Status
    ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID")
    
    # Count Groups
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID")
    
    # Count Translated Groups (Spanish name not empty)
    GROUP_ES_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_group_l10ns gl JOIN lime_groups g ON gl.gid=g.gid WHERE g.sid=$SID AND gl.language='es' AND gl.group_name != ''")
    
    # Count Questions (Top level)
    QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0")
    
    # Count Translated Questions
    QUESTION_ES_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_question_l10ns ql JOIN lime_questions q ON ql.qid=q.qid WHERE q.sid=$SID AND q.parent_qid=0 AND ql.language='es' AND ql.question != ''")
    
    # Check for Array Subquestions (Institutional Confidence)
    # Looking for a parent question of type Array (F, H, etc) that has children
    ARRAY_SUBQ_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions sub JOIN lime_questions parent ON sub.parent_qid = parent.qid WHERE parent.sid=$SID AND parent.type IN ('F','H','1','A','B','C','E')")

    # Check for Translated Answer Options
    # We join answers -> answer_l10ns filtered by 'es'
    ANSWER_OPTION_ES_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_answer_l10ns al JOIN lime_answers a ON al.aid=a.aid JOIN lime_questions q ON a.qid=q.qid WHERE q.sid=$SID AND al.language='es' AND al.answer != ''")
fi

# Sanitize strings for JSON
TITLE_EN_SAFE=$(echo "$TITLE_EN" | sed 's/"/\\"/g' | tr -d '\n')
TITLE_ES_SAFE=$(echo "$TITLE_ES" | sed 's/"/\\"/g' | tr -d '\n')
LANGUAGES_SAFE=$(echo "$LANGUAGES" | sed 's/"/\\"/g' | tr -d '\n')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "title_en": "$TITLE_EN_SAFE",
    "title_es": "$TITLE_ES_SAFE",
    "additional_languages": "$LANGUAGES_SAFE",
    "active": "$ACTIVE",
    "group_count": $GROUP_COUNT,
    "group_es_count": $GROUP_ES_COUNT,
    "question_count": $QUESTION_COUNT,
    "question_es_count": $QUESTION_ES_COUNT,
    "array_subq_count": $ARRAY_SUBQ_COUNT,
    "answer_option_es_count": $ANSWER_OPTION_ES_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="