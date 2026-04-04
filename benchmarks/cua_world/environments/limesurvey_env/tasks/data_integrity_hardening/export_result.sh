#!/bin/bash
echo "=== Exporting Data Integrity Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Database query helper
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# 1. Find the survey ID
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE ls.surveyls_title LIKE 'Hypertension Study%' LIMIT 1")

if [ -z "$SID" ]; then
    echo "Survey not found!"
    cat > /tmp/task_result.json << EOF
{
    "survey_found": false,
    "error": "Survey not found in database"
}
EOF
    exit 0
fi

# 2. Extract configuration for each question
# We need: preg (regex), em_validation_q (equation), and attributes (min/max)

# SUBJID (Regex)
SUBJID_DATA=$(limesurvey_query "SELECT preg, question, help FROM lime_questions q JOIN lime_question_l10ns ql ON q.qid=ql.qid WHERE q.sid=$SID AND q.title='SUBJID' LIMIT 1")
REGEX_VAL=$(echo "$SUBJID_DATA" | cut -f1)
SUBJID_HELP=$(echo "$SUBJID_DATA" | cut -f3) # Tip usually stored in help or question text depending on LimeSurvey version/theme usage

# BP_SYS (Attributes)
# Attributes are stored in lime_question_attributes: qid, attribute, value
BP_SYS_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='BP_SYS'")
BP_SYS_MIN=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid='$BP_SYS_QID' AND attribute='min_num_value_n'")
BP_SYS_MAX=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid='$BP_SYS_QID' AND attribute='max_num_value_n'")

# BP_DIA (Attributes)
BP_DIA_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='BP_DIA'")
BP_DIA_MIN=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid='$BP_DIA_QID' AND attribute='min_num_value_n'")
BP_DIA_MAX=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid='$BP_DIA_QID' AND attribute='max_num_value_n'")

# SCREEN_DATE (Equation)
SCREEN_DATE_DATA=$(limesurvey_query "SELECT em_validation_q, question, help FROM lime_questions q JOIN lime_question_l10ns ql ON q.qid=ql.qid WHERE q.sid=$SID AND q.title='SCREEN_DATE' LIMIT 1")
DATE_EQ=$(echo "$SCREEN_DATE_DATA" | cut -f1)
DATE_HELP=$(echo "$SCREEN_DATE_DATA" | cut -f3)

# Escape strings for JSON
safe_json() {
    echo "$1" | sed 's/"/\\"/g' | sed 's/	/ /g' | tr -d '\n'
}

REGEX_VAL_SAFE=$(safe_json "$REGEX_VAL")
SUBJID_HELP_SAFE=$(safe_json "$SUBJID_HELP")
DATE_EQ_SAFE=$(safe_json "$DATE_EQ")
DATE_HELP_SAFE=$(safe_json "$DATE_HELP")

# Construct JSON
cat > /tmp/result.json << EOF
{
    "survey_found": true,
    "sid": "$SID",
    "subjid": {
        "regex": "$REGEX_VAL_SAFE",
        "help_text": "$SUBJID_HELP_SAFE"
    },
    "bp_sys": {
        "min": "${BP_SYS_MIN:-null}",
        "max": "${BP_SYS_MAX:-null}"
    },
    "bp_dia": {
        "min": "${BP_DIA_MIN:-null}",
        "max": "${BP_DIA_MAX:-null}"
    },
    "screen_date": {
        "equation": "$DATE_EQ_SAFE",
        "help_text": "$DATE_HELP_SAFE"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete:"
cat /tmp/task_result.json